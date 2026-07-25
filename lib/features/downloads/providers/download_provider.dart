import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:epubx/epubx.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/providers/engine.dart';
import '../../../core/providers/registry.dart';
import '../../../core/network/client.dart';
import '../../../core/utils/logger.dart';
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

  double get progress => totalChapters == 0 ? 0 : completedChapters / totalChapters;
}

class DownloadNotifier extends StateNotifier<Map<int, NovelDownloadProgress>> {
  final Ref ref;
  bool _isProcessing = false;

  DownloadNotifier(this.ref) : super({});

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
    await downloadDao.enqueueDownload(DownloadsQueueCompanion(
      novelId: Value(novelId),
      chapterId: Value(chapterId),
      status: const Value('queued'),
      progress: const Value(0.0),
    ));

    Log.i(_tag, 'Enqueued chapter $chapterId for novel $novelId');
    _updateProgress(novelId);
    _processQueue();
  }

  /// Download all chapters for a novel
  Future<void> downloadAllChapters(int novelId) async {
    final chapterDao = ref.read(chapterDaoProvider);
    final chapters = await chapterDao.getChaptersForNovel(novelId);

    Log.i(_tag, 'Downloading all ${chapters.length} chapters for novel $novelId');

    for (final chapter in chapters) {
      await downloadChapter(novelId, chapter.id);
    }
  }

  /// Download a range of chapters
  Future<void> downloadChapterRange(int novelId, int start, int end) async {
    final chapterDao = ref.read(chapterDaoProvider);
    final chapters = await chapterDao.getChaptersForNovel(novelId);

    final range = chapters.where((c) => c.index >= start && c.index <= end).toList();
    Log.i(_tag, 'Downloading ${range.length} chapters (range $start-$end) for novel $novelId');

    for (final chapter in range) {
      await downloadChapter(novelId, chapter.id);
    }
  }

  /// Process the download queue
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    // Start background service for Android (keeps downloads running when app is backgrounded)
    BackgroundDownloadService.start();

    try {
      final downloadDao = ref.read(downloadDaoProvider);
      final pending = await downloadDao.getPendingDownloads();

      if (pending.isEmpty) {
        _isProcessing = false;
        BackgroundDownloadService.stop();
        return;
      }

      for (final task in pending) {
        await _downloadTask(task);
      }
    } finally {
      _isProcessing = false;
      BackgroundDownloadService.stop();
    }
  }

  /// Download a single task
  Future<void> _downloadTask(DownloadsQueueData task) async {
    final downloadDao = ref.read(downloadDaoProvider);
    final chapterDao = ref.read(chapterDaoProvider);

    try {
      // Mark as downloading
      await downloadDao.updateDownloadStatus(task.id, 'downloading', progress: 0.0);
      _updateProgress(task.novelId);

      // Get chapter info
      final chapter = await chapterDao.getChapterById(task.chapterId);
      if (chapter == null) {
        await downloadDao.updateDownloadStatus(task.id, 'failed', error: 'Chapter not found');
        _updateProgress(task.novelId);
        return;
      }

      // Skip EPUB/PDF chapters (already local)
      if (chapter.url.startsWith('epub://') || chapter.url.startsWith('pdf://')) {
        await downloadDao.updateDownloadStatus(task.id, 'done', progress: 1.0);
        _updateProgress(task.novelId);
        return;
      }

      // Get provider info
      final novelDao = ref.read(novelDaoProvider);
      final novel = await novelDao.getNovelById(task.novelId);
      if (novel == null) {
        await downloadDao.updateDownloadStatus(task.id, 'failed', error: 'Novel not found');
        _updateProgress(task.novelId);
        return;
      }

      final registry = await ref.read(registryManagerProvider.future);
      final engine = ref.read(providerEngineProvider);
      final dio = await ref.read(dioProvider.future);

      Log.d(_tag, 'Loading provider JS for: ${novel.providerId}');
      final jsSource = await registry.loadCachedProviderJs(novel.providerId);
      if (jsSource == null) {
        await downloadDao.updateDownloadStatus(task.id, 'failed', error: 'Provider JS not found for ${novel.providerId}');
        _updateProgress(task.novelId);
        return;
      }

      Log.d(_tag, 'Loading provider instance...');
      final instance = await engine.loadProvider(jsSource);

      Log.d(_tag, 'Getting content URL for: ${chapter.url}');
      final contentUrl = await instance.getChapterContentUrl(chapter.url);
      if (contentUrl == null) {
        await downloadDao.updateDownloadStatus(task.id, 'failed', error: 'getChapterContentUrl returned null');
        _updateProgress(task.novelId);
        return;
      }

      Log.d(_tag, 'Downloading: $contentUrl');

      // Download with retries
      String? html;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          final response = await dio.get(contentUrl);
          html = response.data.toString();
          break;
        } catch (e) {
          Log.w(_tag, 'Download attempt ${attempt + 1} failed: $e');
          if (attempt < 2) {
            await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          }
        }
      }

      if (html == null) {
        await downloadDao.updateDownloadStatus(task.id, 'failed', error: 'Failed to download');
        _updateProgress(task.novelId);
        return;
      }

      // Parse content
      final content = await instance.parseChapterContent(html);
      if (content == null) {
        await downloadDao.updateDownloadStatus(task.id, 'failed', error: 'Failed to parse content');
        _updateProgress(task.novelId);
        return;
      }

      // Save as EPUB
      final dir = await _getDownloadDir(novel);
      final fileName = '${task.chapterId}.epub';
      final file = File(p.join(dir.path, fileName));

      final chapterHtml = content.html;
      final chapterTitle = chapter.name;
      final novelTitle = novel.title ?? 'Unknown';
      final novelAuthor = novel.author ?? '';

      final epubBook = EpubBook()
        ..Title = chapterTitle
        ..Author = novelAuthor
        ..Chapters = [
          EpubChapter()
            ..Title = chapterTitle
            ..ContentFileName = '${task.chapterId}.xhtml'
            ..HtmlContent = chapterHtml,
        ]
        ..Content = (EpubContent()
          ..Html = {
            '${task.chapterId}.xhtml': (EpubTextContentFile()
              ..Content = chapterHtml
              ..ContentMimeType = 'application/xhtml+xml'),
          });

      final epubBytes = EpubWriter.writeBook(epubBook);
      if (epubBytes != null) {
        await file.writeAsBytes(epubBytes);
      } else {
        // Fallback: save as HTML if EPUB generation fails
        final chapterDaoFallback = ref.read(chapterDaoProvider);
        final htmlFile = File(p.join(dir.path, '${task.chapterId}.html'));
        await htmlFile.writeAsString(content.html);
        await chapterDaoFallback.markChapterAsDownloaded(task.chapterId, htmlFile.path);
        await downloadDao.updateDownloadStatus(task.id, 'done', progress: 1.0);
        _updateProgress(task.novelId);
        Log.ok(_tag, 'Chapter ${chapter.name} downloaded (HTML fallback) to ${htmlFile.path}');
        return;
      }

      // Update chapter as downloaded
      final chapterDao2 = ref.read(chapterDaoProvider);
      await chapterDao2.markChapterAsDownloaded(task.chapterId, file.path);

      // Mark task as done
      await downloadDao.updateDownloadStatus(task.id, 'done', progress: 1.0);
      _updateProgress(task.novelId);

      Log.ok(_tag, 'Chapter ${chapter.name} downloaded to ${file.path}');
    } catch (e, stackTrace) {
      Log.e(_tag, 'Download failed for task ${task.id}: $e');
      Log.e(_tag, 'Stack: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      await downloadDao.updateDownloadStatus(task.id, 'failed', error: e.toString());
      _updateProgress(task.novelId);
    }
  }

  Future<Directory> _getDownloadDir(Novel novel) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(
      appDir.path,
      'downloads',
      novel.providerId,
      novel.title.replaceAll(RegExp(r'[^\w\s-]'), ''),
    ));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  void _updateProgress(int novelId) async {
    final downloadDao = ref.read(downloadDaoProvider);
    final chapterDao = ref.read(chapterDaoProvider);

    final allChapters = await chapterDao.getChaptersForNovel(novelId);
    final downloads = await downloadDao.getAllDownloads();
    final novelDownloads = downloads.where((d) => d.novelId == novelId).toList();

    final completed = novelDownloads.where((d) => d.status == 'done').length;
    final failed = novelDownloads.where((d) => d.status == 'failed').length;
    final isDownloading = novelDownloads.any((d) => d.status == 'downloading' || d.status == 'queued');

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
        novelTitle: title,
        completed: completed,
        total: allChapters.length,
      );
      // Also update background service notification
      BackgroundDownloadService.updateNotification(
        title: 'Downloading: $title',
        content: '$completed/$allChapters.length chapters',
      );
    } else if (completed > 0 && !isDownloading) {
      final novelDao = ref.read(novelDaoProvider);
      final novel = await novelDao.getNovelById(novelId);
      DownloadNotification.showComplete(
        novelTitle: novel?.title ?? 'Unknown',
        total: completed,
      );
    }
  }

  /// Cancel all downloads for a novel
  Future<void> cancelDownloads(int novelId) async {
    final downloadDao = ref.read(downloadDaoProvider);
    final downloads = await downloadDao.getAllDownloads();
    for (final d in downloads.where((d) => d.novelId == novelId && (d.status == 'queued' || d.status == 'downloading'))) {
      await downloadDao.removeDownload(d.id);
    }
    _updateProgress(novelId);
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

    _updateProgress(novelId);
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

final downloadProvider = StateNotifierProvider<DownloadNotifier, Map<int, NovelDownloadProgress>>((ref) {
  return DownloadNotifier(ref);
});
