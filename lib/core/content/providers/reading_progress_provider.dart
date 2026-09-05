import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/providers/engine.dart';
import '../../../core/providers/registry.dart';
import '../../../core/utils/logger.dart';

part 'reading_progress_provider.g.dart';

const _tag = 'ReadingProgress';

class ReadingProgressState {
  final int novelId;
  final int totalChapters;
  final int readChapters;
  final int currentChapterIndex;
  final double overallProgress; // 0.0 - 1.0
  final bool isCompleted;
  final DateTime? lastSyncedAt;
  final bool isSyncing;
  final String? syncError;

  const ReadingProgressState({
    required this.novelId,
    this.totalChapters = 0,
    this.readChapters = 0,
    this.currentChapterIndex = 0,
    this.overallProgress = 0.0,
    this.isCompleted = false,
    this.lastSyncedAt,
    this.isSyncing = false,
    this.syncError,
  });

  ReadingProgressState copyWith({
    int? totalChapters,
    int? readChapters,
    int? currentChapterIndex,
    double? overallProgress,
    bool? isCompleted,
    DateTime? lastSyncedAt,
    bool? isSyncing,
    String? syncError,
  }) {
    return ReadingProgressState(
      novelId: novelId,
      totalChapters: totalChapters ?? this.totalChapters,
      readChapters: readChapters ?? this.readChapters,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      overallProgress: overallProgress ?? this.overallProgress,
      isCompleted: isCompleted ?? this.isCompleted,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      isSyncing: isSyncing ?? this.isSyncing,
      syncError: syncError ?? this.syncError,
    );
  }
}

@Riverpod(keepAlive: true)
class ReadingProgressNotifier extends _$ReadingProgressNotifier {
  Timer? _syncTimer;

  @override
  ReadingProgressState build(int novelId) {
    _loadProgress();
    _startBackgroundSync();
    ref.onDispose(() => _syncTimer?.cancel());
    return ReadingProgressState(novelId: novelId);
  }

  Future<void> _loadProgress() async {
    try {
      final chapterDao = ref.read(chapterDaoProvider);
      final historyDao = ref.read(historyDaoProvider);
      final novelId = state.novelId;

      final total = await chapterDao.getChapterCount(novelId);
      final chapters = await chapterDao.getChaptersForNovel(novelId);
      final readCount = chapters.where((c) => c.read).length;
      final lastHistory = await historyDao.getLatestHistoryForNovel(novelId);

      int currentIndex = 0;
      if (lastHistory != null) {
        currentIndex = chapters.indexWhere(
          (c) => c.id == lastHistory.chapterId,
        );
        if (currentIndex < 0) currentIndex = 0;
      }

      final progress = total > 0 ? readCount / total : 0.0;
      final completed = total > 0 && readCount >= total;

      state = state.copyWith(
        totalChapters: total,
        readChapters: readCount,
        currentChapterIndex: currentIndex,
        overallProgress: progress,
        isCompleted: completed,
      );
    } catch (e) {
      Log.e(
        _tag,
        'Failed to load reading progress for novel ${state.novelId}',
        e,
      );
    }
  }

  void _startBackgroundSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (!state.isSyncing) {
        syncWithServer();
      }
    });
  }

  Future<void> syncWithServer() async {
    if (state.isSyncing) return;

    state = state.copyWith(isSyncing: true, syncError: null);

    try {
      final chapterDao = ref.read(chapterDaoProvider);
      final novelDao = ref.read(novelDaoProvider);
      final novelId = state.novelId;

      final novel = await novelDao.getNovelById(novelId);
      if (novel == null) return;

      final registry = await ref.read(registryManagerProvider.future);
      final engine = ref.read(providerEngineProvider);
      final jsSource = await registry.loadCachedProviderJs(novel.providerId);
      if (jsSource == null) {
        state = state.copyWith(
          isSyncing: false,
          syncError: 'Provider not found',
        );
        return;
      }
      final provider = await engine.loadProvider(jsSource);

      final result = await provider.call('getChapterList', [novel.url]);
      final chapterUrls = result as List<dynamic>?;
      if (chapterUrls == null) {
        state = state.copyWith(
          isSyncing: false,
          syncError: 'Failed to fetch chapter list',
        );
        return;
      }

      final existingChapters = await chapterDao.getChaptersForNovel(novelId);
      final existingUrls = existingChapters.map((c) => c.url).toSet();

      // One diff-sync for the whole batch. The previous per-chapter loop
      // called delete-all + insert-one on every iteration, which wiped the
      // novel's entire chapter list and left only the last entry.
      final chapterList = [
        for (final chapterUrl in chapterUrls)
          if (!existingUrls.contains(chapterUrl['url']))
            ChaptersCompanion(
              novelId: Value(novelId),
              name: Value(chapterUrl['name'] as String),
              url: Value(chapterUrl['url'] as String),
              index: Value((chapterUrl['index'] as num).toDouble()),
            ),
      ];
      await chapterDao.syncChaptersForNovel(novelId, chapterList);
      final newChapters = chapterList.length;

      await _loadProgress();

      state = state.copyWith(
        isSyncing: false,
        lastSyncedAt: DateTime.now(),
        syncError: null,
      );

      Log.i(_tag, 'Synced novel $novelId: $newChapters new chapters');
    } catch (e) {
      Log.e(_tag, 'Sync failed for novel ${state.novelId}', e);
      state = state.copyWith(isSyncing: false, syncError: e.toString());
    }
  }

  Future<void> markChapterAsRead(int chapterId) async {
    final chapterDao = ref.read(chapterDaoProvider);
    await chapterDao.markChapterAsRead(chapterId);
    await _loadProgress();
  }

  Future<void> updateCurrentChapter(int chapterIndex) async {
    state = state.copyWith(currentChapterIndex: chapterIndex);
    await _loadProgress();
  }
}

/// Provider to get all novels with their reading progress.
/// The only autoDispose provider in the app.
@Riverpod(keepAlive: false)
Future<List<NovelProgress>> allReadingProgress(Ref ref) async {
  final novelDao = ref.read(novelDaoProvider);
  final novels = await novelDao.getAllNovels();

  final results = <NovelProgress>[];
  for (final novel in novels) {
    final chapterDao = ref.read(chapterDaoProvider);
    final chapters = await chapterDao.getChaptersForNovel(novel.id);
    final total = chapters.length;
    final read = chapters.where((c) => c.read).length;
    final lastHistory = await ref
        .read(historyDaoProvider)
        .getLatestHistoryForNovel(novel.id);

    int currentIndex = 0;
    if (lastHistory != null) {
      currentIndex = chapters.indexWhere((c) => c.id == lastHistory.chapterId);
      if (currentIndex < 0) currentIndex = 0;
    }

    results.add(
      NovelProgress(
        novelId: novel.id,
        title: novel.title,
        totalChapters: total,
        readChapters: read,
        currentChapterIndex: currentIndex,
        overallProgress: total > 0 ? read / total : 0.0,
        isCompleted: total > 0 && read >= total,
      ),
    );
  }
  return results;
}

class NovelProgress {
  final int novelId;
  final String title;
  final int totalChapters;
  final int readChapters;
  final int currentChapterIndex;
  final double overallProgress;
  final bool isCompleted;

  const NovelProgress({
    required this.novelId,
    required this.title,
    required this.totalChapters,
    required this.readChapters,
    required this.currentChapterIndex,
    required this.overallProgress,
    required this.isCompleted,
  });
}
