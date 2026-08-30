import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../../core/content/markdown/html2md.dart';
import '../../../core/database/database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/providers/engine.dart';
import '../../../core/network/client.dart';
import '../../../core/utils/logger.dart';
import '../../settings/pages/download_settings_page.dart';
import '../background_service.dart';
import 'download_notification.dart';

const _tag = 'Download';

/// Download task state
class DownloadTaskState {
  final int novelId;
  final int chapterId;
  final String status; // queued, downloading, done, failed
  final double progress;
  final String? error;

  const DownloadTaskState({
    required this.novelId,
    required this.chapterId,
    this.status = 'queued',
    this.progress = 0.0,
    this.error,
  });
}

/// Download progress for a novel
class NovelDownloadProgress {
  final int novelId;
  final int totalChapters;
  final int completedChapters;
  final int failedChapters;
  final bool isDownloading;

  const NovelDownloadProgress({
    required this.novelId,
    required this.totalChapters,
    this.completedChapters = 0,
    this.failedChapters = 0,
    this.isDownloading = false,
  });

  double get progress =>
      totalChapters == 0 ? 0 : completedChapters / totalChapters;
}

class DownloadNotifier extends StateNotifier<Map<int, NovelDownloadProgress>> {
  final Ref ref;
  bool _isProcessing = false;

  /// The task currently being downloaded, if any. Closing its tile deletes
  /// its row; the pipeline checks row existence before touching disk or DB.
  int? _currentTaskId;

  DownloadNotifier(this.ref) : super({}) {
    // Route notification Cancel actions into the pipeline.
    DownloadNotification.onCancelRequest = cancelDownloads;
  }

  /// Download a single chapter
  Future<void> downloadChapter(int novelId, int chapterId) async {
    final downloadDao = ref.read(downloadDaoProvider);

    // Check if already queued
    final existing = await downloadDao.getQueuedDownload(novelId, chapterId);
    if (existing != null) {
      Log.d(_tag, 'Chapter $chapterId already queued');
      return;
    }

    // Enqueue
    await downloadDao.enqueueDownload(
      DownloadsQueueCompanion(
        novelId: Value(novelId),
        chapterId: Value(chapterId),
        status: const Value('queued'),
        progress: const Value(0.0),
      ),
    );

    Log.i(_tag, 'Enqueued chapter $chapterId for novel $novelId');
    await _updateProgress(novelId);
    _processQueue();
  }

  /// Download all chapters for a novel
  Future<void> downloadAllChapters(int novelId) async {
    final chapterDao = ref.read(chapterDaoProvider);
    final chapters = await chapterDao.getChaptersForNovel(novelId);

    Log.i(
      _tag,
      'Downloading all ${chapters.length} chapters for novel $novelId',
    );

    for (final chapter in chapters) {
      await downloadChapter(novelId, chapter.id);
    }
  }

  /// Download a range of chapters
  Future<void> downloadChapterRange(int novelId, int start, int end) async {
    final chapterDao = ref.read(chapterDaoProvider);
    final chapters = await chapterDao.getChaptersForNovel(novelId);

    final range = chapters
        .where((c) => c.index >= start && c.index <= end)
        .toList();
    Log.i(
      _tag,
      'Downloading ${range.length} chapters (range $start-$end) for novel $novelId',
    );

    for (final chapter in range) {
      await downloadChapter(novelId, chapter.id);
    }
  }

  /// Process the download queue until it is empty.
  ///
  /// Workers pull tasks by atomically claiming them, so tasks enqueued while
  /// the pool is running are picked up instead of waiting for the next
  /// external trigger (the old snapshot-once loop could strand them).
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    // Start background service for Android (keeps downloads running when app is backgrounded)
    BackgroundDownloadService.start();

    try {
      final settings = ref.read(downloadSettingsProvider);

      // Honor the Wi-Fi only setting; tasks stay queued until it lifts.
      if (settings.wifiOnly && !await _onWifi()) {
        Log.i(_tag, 'Wi-Fi only is on and no Wi-Fi; queue deferred');
        return;
      }

      final workers = List.generate(
        settings.parallelDownloads.clamp(1, 5),
        (_) => _worker(),
      );
      await Future.wait(workers);
    } finally {
      _isProcessing = false;

      // New tasks may have been enqueued while the pool ran (or a cancelled
      // task left siblings behind). Keep draining instead of stranding them.
      final downloadDao = ref.read(downloadDaoProvider);
      final pending = await downloadDao.getPendingDownloads();
      if (pending.isNotEmpty) {
        unawaited(_processQueue());
      } else {
        _currentTaskId = null;
        BackgroundDownloadService.stop();
      }
    }
  }

  /// Pulls claimable tasks until the queue runs dry.
  Future<void> _worker() async {
    final downloadDao = ref.read(downloadDaoProvider);

    while (true) {
      final task = await downloadDao.claimNextQueued();
      if (task == null) break;

      _currentTaskId = task.id;
      try {
        await _downloadTask(task);
      } finally {
        if (_currentTaskId == task.id) _currentTaskId = null;
      }
    }
  }

  /// True when Wi-Fi only is off, or a non-metered connection exists.
  Future<bool> _onWifi() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
    } catch (e) {
      Log.w(_tag, 'Connectivity check failed: $e');
      return true; // fail open rather than stall the queue silently
    }
  }

  /// Requeues tasks stuck in 'downloading' from a previous session and
  /// restarts processing. Called when the Downloads screen opens.
  Future<void> resumePendingDownloads() async {
    final downloadDao = ref.read(downloadDaoProvider);
    await downloadDao.requeueStaleDownloading();

    final pending = await downloadDao.getPendingDownloads();
    for (final novelId in pending.map((t) => t.novelId).toSet()) {
      await _updateProgress(novelId);
    }

    unawaited(_processQueue());
  }

  /// Re-queues one failed (or stale) task and kicks processing.
  Future<void> retryTask(int taskId) async {
    final downloadDao = ref.read(downloadDaoProvider);
    await downloadDao.updateDownloadStatus(
      taskId,
      'queued',
      progress: 0,
      error: null,
    );
    unawaited(_processQueue());
  }

  /// Removes one task. If it is the in-flight download, its remaining work
  /// (file write, status updates) is skipped by the pipeline's checkpoints.
  Future<void> cancelTask(int taskId) async {
    await ref.read(downloadDaoProvider).removeDownload(taskId);
    unawaited(_processQueue());
  }

  /// Re-queues every failed task of a novel and kicks processing.
  Future<void> retryFailed(int novelId) async {
    final downloadDao = ref.read(downloadDaoProvider);
    final downloads = await downloadDao.getAllDownloads();
    for (final d in downloads.where(
      (d) => d.novelId == novelId && d.status == 'failed',
    )) {
      await downloadDao.updateDownloadStatus(
        d.id,
        'queued',
        progress: 0,
        error: null,
      );
    }
    unawaited(_processQueue());
  }

  /// Download a single task
  Future<void> _downloadTask(DownloadsQueueData task) async {
    final downloadDao = ref.read(downloadDaoProvider);
    final chapterDao = ref.read(chapterDaoProvider);

    try {
      // Row deleted while we waited on a worker slot: user cancelled it.
      if (await downloadDao.getDownloadById(task.id) == null) return;

      await downloadDao.updateDownloadStatus(
        task.id,
        'downloading',
        progress: 0.0,
      );
      await _updateProgress(task.novelId);

      // Get chapter info
      final chapter = await chapterDao.getChapterById(task.chapterId);
      if (chapter == null) {
        await downloadDao.updateDownloadStatus(
          task.id,
          'failed',
          error: 'Chapter not found',
        );
        await _updateProgress(task.novelId);
        return;
      }

      // Skip EPUB/PDF chapters (already local)
      if (chapter.url.startsWith('epub://') ||
          chapter.url.startsWith('pdf://')) {
        await downloadDao.updateDownloadStatus(task.id, 'done', progress: 1.0);
        await _updateProgress(task.novelId);
        return;
      }

      // Get provider info
      final novelDao = ref.read(novelDaoProvider);
      final novel = await novelDao.getNovelById(task.novelId);
      if (novel == null) {
        await downloadDao.updateDownloadStatus(
          task.id,
          'failed',
          error: 'Novel not found',
        );
        await _updateProgress(task.novelId);
        return;
      }

      final dio = await ref.read(dioProvider.future);

      Log.d(_tag, 'Loading provider instance for: ${novel.providerId}');
      // Single shared load path: caches per provider id, dedupes concurrent
      // loads, and loads feature flags.
      final instance = await ref.read(
        providerInstanceProvider(novel.providerId).future,
      );
      if (instance == null) {
        await downloadDao.updateDownloadStatus(
          task.id,
          'failed',
          error: 'Provider not found for ${novel.providerId}',
        );
        await _updateProgress(task.novelId);
        return;
      }

      Log.d(_tag, 'Getting content URL for: ${chapter.url}');
      final contentUrl = await instance.getChapterContentUrl(chapter.url);
      if (contentUrl == null) {
        await downloadDao.updateDownloadStatus(
          task.id,
          'failed',
          error: 'getChapterContentUrl returned null',
        );
        await _updateProgress(task.novelId);
        return;
      }

      Log.d(_tag, 'Downloading: $contentUrl');

      // Download. Retries are handled centrally by the Dio interceptor in
      // core/network/client.dart, so a failure here is final.
      String? html;
      try {
        final response = await dio.get(contentUrl);
        html = response.data.toString();
      } catch (e) {
        Log.w(_tag, 'Download failed: $e');
      }

      if (html == null) {
        await downloadDao.updateDownloadStatus(
          task.id,
          'failed',
          error: 'Failed to download',
        );
        await _updateProgress(task.novelId);
        return;
      }

      // Parse content
      final content = await instance.parseChapterContent(html);
      if (content == null || content.html.trim().isEmpty) {
        await downloadDao.updateDownloadStatus(
          task.id,
          'failed',
          error: 'Failed to parse content',
        );
        await _updateProgress(task.novelId);
        return;
      }

      // Cancelled while the network request ran? Do not touch disk or DB.
      final stillQueued = await downloadDao.getDownloadById(task.id);
      if (stillQueued == null) {
        Log.i(_tag, 'Task ${task.id} cancelled before save');
        return;
      }

      // Save as Markdown
      final dir = await _getDownloadDir(novel);
      final fileName = '${task.chapterId}.md';
      final file = File(p.join(dir.path, fileName));

      final markdown = Html2Md.convert(content.html);

      // Integrity: refuse to persist an empty conversion. A done-marked
      // chapter with an empty file would serve broken content in the reader.
      if (markdown.trim().isEmpty) {
        await downloadDao.updateDownloadStatus(
          task.id,
          'failed',
          error: 'Converted content was empty',
        );
        await _updateProgress(task.novelId);
        return;
      }

      await file.writeAsString(markdown);

      // Update chapter as downloaded
      final chapterDao2 = ref.read(chapterDaoProvider);
      await chapterDao2.markChapterAsDownloaded(task.chapterId, file.path);

      // Mark task as done
      await downloadDao.updateDownloadStatus(task.id, 'done', progress: 1.0);
      await _updateProgress(task.novelId);

      Log.ok(_tag, 'Chapter ${chapter.name} downloaded to ${file.path}');
    } catch (e, stackTrace) {
      Log.e(_tag, 'Download failed for task ${task.id}: $e');
      Log.e(
        _tag,
        'Stack: ${stackTrace.toString().split('\n').take(5).join('\n')}',
      );
      await downloadDao.updateDownloadStatus(
        task.id,
        'failed',
        error: e.toString(),
      );
      await _updateProgress(task.novelId);
    }
  }

  Future<Directory> _getDownloadDir(Novel novel) async {
    final settings = ref.read(downloadSettingsProvider);
    var basePath = settings.downloadPath;
    if (basePath.isEmpty) {
      final appDir = await getApplicationDocumentsDirectory();
      basePath = p.join(appDir.path, 'downloads');
    }
    final dir = Directory(
      p.join(
        basePath,
        novel.providerId,
        // Non-Latin titles can sanitize to an empty string; without a
        // fallback, every such novel shares one directory (and the orphan
        // scanner would delete their files as belonging to the wrong novel).
        novel.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim().isEmpty
            ? 'novel-${novel.id}'
            : novel.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim(),
      ),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _updateProgress(int novelId) async {
    final downloadDao = ref.read(downloadDaoProvider);
    final chapterDao = ref.read(chapterDaoProvider);

    final allChapters = await chapterDao.getChaptersForNovel(novelId);
    final downloads = await downloadDao.getAllDownloads();
    final novelDownloads = downloads
        .where((d) => d.novelId == novelId)
        .toList();

    final completed = novelDownloads.where((d) => d.status == 'done').length;
    final failed = novelDownloads.where((d) => d.status == 'failed').length;
    final isDownloading = novelDownloads.any(
      (d) => d.status == 'downloading' || d.status == 'queued',
    );

    state = {
      ...state,
      novelId: NovelDownloadProgress(
        novelId: novelId,
        totalChapters: allChapters.length,
        completedChapters: completed,
        failedChapters: failed,
        isDownloading: isDownloading,
      ),
    };

    // Update download notification
    DownloadNotification.init(); // no-op if already initialized
    if (isDownloading) {
      final novelDao = ref.read(novelDaoProvider);
      final novel = await novelDao.getNovelById(novelId);
      final title = novel?.title ?? 'Unknown';
      DownloadNotification.showProgress(
        novelId: novelId,
        novelTitle: title,
        completed: completed,
        total: allChapters.length,
        failed: failed,
      );
    } else if (completed > 0) {
      final novelDao = ref.read(novelDaoProvider);
      final novel = await novelDao.getNovelById(novelId);
      DownloadNotification.showComplete(
        novelId: novelId,
        novelTitle: novel?.title ?? 'Unknown',
        total: completed,
        failed: failed,
      );
    } else {
      // Cancelled/deleted before anything completed; clear any stale
      // progress notification for this novel.
      unawaited(DownloadNotification.hide(novelId));
    }
  }

  /// Cancel all downloads for a novel. Deleted rows are the cancel signal;
  /// in-flight tasks notice and skip their remaining work.
  Future<void> cancelDownloads(int novelId) async {
    final downloadDao = ref.read(downloadDaoProvider);
    final downloads = await downloadDao.getAllDownloads();
    for (final d in downloads.where(
      (d) =>
          d.novelId == novelId &&
          (d.status == 'queued' || d.status == 'downloading'),
    )) {
      await downloadDao.removeDownload(d.id);
    }
    await _updateProgress(novelId);
  }

  /// Delete downloaded files for a novel
  Future<void> deleteDownloads(int novelId) async {
    final chapterDao = ref.read(chapterDaoProvider);
    final chapters = await chapterDao.getChaptersForNovel(novelId);

    for (final chapter in chapters) {
      if (chapter.downloadedPath != null) {
        final file = File(chapter.downloadedPath!);
        if (await file.exists()) {
          await file.delete();
        }
        await chapterDao.markNotDownloaded(chapter.id);
      }
    }

    // Clean up queue
    final downloadDao = ref.read(downloadDaoProvider);
    final downloads = await downloadDao.getAllDownloads();
    for (final d in downloads.where((d) => d.novelId == novelId)) {
      await downloadDao.removeDownload(d.id);
    }

    await _updateProgress(novelId);
  }

  /// Reconciles download state between the database and the filesystem.
  ///
  /// - Chapters flagged downloaded whose .md file has vanished (deleted
  ///   externally, cleared app storage) get their flag cleared so the UI
  ///   stops claiming content that no longer exists.
  /// - Numeric `<chapterId>.md/.epub/.html` files with no matching DB row
  ///   are orphaned leftovers; they are deleted. Legacy `.epub`/`.html`
  ///   files beside a chapter's current `.md` are superseded; deleted too.
  ///
  /// Safe to call repeatedly. Returns the number of repaired entries.
  Future<int> reconcileDownloads({int? novelId}) async {
    var repairs = 0;
    final chapterDao = ref.read(chapterDaoProvider);
    final novelDao = ref.read(novelDaoProvider);

    final List<Novel> novels;
    if (novelId == null) {
      novels = await novelDao.getAllNovels();
    } else {
      final single = await novelDao.getNovelById(novelId);
      novels = single == null ? [] : [single];
    }

    // ── Stale flags: DB says downloaded, file missing ──
    final stale = <int>[];
    for (final novel in novels) {
      final chapters = await chapterDao.getDownloadedChapters(novel.id);
      for (final chapter in chapters) {
        final path = chapter.downloadedPath;
        if (path == null || path.isEmpty) continue;
        if (!File(path).existsSync()) stale.add(chapter.id);
      }
    }
    for (final id in stale) {
      await chapterDao.markNotDownloaded(id);
      repairs++;
    }
    if (stale.isNotEmpty) {
      Log.i(_tag, 'Cleared ${stale.length} stale download flags');
    }

    // ── Orphan files & legacy formats: on disk, but unknown/superseded ──
    for (final novel in novels) {
      try {
        final dir = await _getDownloadDir(novel);
        final chapters = await chapterDao.getChaptersForNovel(novel.id);
        final knownIds = {
          for (final c in chapters)
            if (c.downloaded) c.id,
        };
        // Current on-disk format per chapter, e.g. {42: '.md'}.
        final currentExt = {
          for (final c in chapters)
            if (c.downloaded &&
                c.downloadedPath != null &&
                c.downloadedPath!.isNotEmpty)
              c.id: p.extension(c.downloadedPath!).toLowerCase(),
        };
        await for (final entry in dir.list()) {
          if (entry is! File) continue;
          final name = p.basename(entry.path);
          final match = RegExp(r'^(\d+)\.(md|epub|html)$').firstMatch(name);
          if (match == null) continue;
          final id = int.parse(match.group(1)!);
          final ext = '.${match.group(2)}';
          // No DB row: orphan leftover. Row exists but stores a newer
          // format: superseded legacy file (.epub/.html beside a .md).
          // Legacy migration lives here rather than in the download
          // pipeline so it costs nothing on the hot path.
          final isSuperseded =
              currentExt.containsKey(id) && currentExt[id] != ext;
          if (!knownIds.contains(id) || isSuperseded) {
            try {
              await entry.delete();
              repairs++;
            } catch (_) {}
          }
        }
      } catch (_) {
        // Directory missing or unreadable: nothing to clean.
      }
    }

    return repairs;
  }

  /// Check if a chapter is downloaded
  Future<bool> isChapterDownloaded(int chapterId) async {
    final chapterDao = ref.read(chapterDaoProvider);
    final chapter = await chapterDao.getChapterById(chapterId);
    if (chapter == null || chapter.downloadedPath == null) return false;
    final file = File(chapter.downloadedPath!);
    return file.exists();
  }
}

final downloadProvider =
    StateNotifierProvider<DownloadNotifier, Map<int, NovelDownloadProgress>>((
      ref,
    ) {
      return DownloadNotifier(ref);
    });
