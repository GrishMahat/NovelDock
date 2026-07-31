import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/utils/logger.dart';
import 'content_provider.dart';

const _tag = 'ReaderNav';

class ReaderNavigationState {
  final List<Chapter> chapters;
  final int currentIndex;
  final bool isLoading;
  final String? error;
  final int novelId;
  final double? restoredScrollPosition;

  const ReaderNavigationState({
    this.chapters = const <Chapter>[],
    this.currentIndex = 0,
    this.isLoading = true,
    this.error,
    required this.novelId,
    this.restoredScrollPosition,
  });

  ReaderNavigationState copyWith({
    List<Chapter>? chapters,
    int? currentIndex,
    bool? isLoading,
    String? error,
    double? restoredScrollPosition,
  }) {
    return ReaderNavigationState(
      chapters: chapters ?? this.chapters,
      currentIndex: currentIndex ?? this.currentIndex,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      novelId: novelId,
      restoredScrollPosition:
          restoredScrollPosition ?? this.restoredScrollPosition,
    );
  }

  Chapter? get currentChapter =>
      currentIndex >= 0 && currentIndex < chapters.length
      ? chapters[currentIndex]
      : null;
}

class ReaderNavigationNotifier extends StateNotifier<ReaderNavigationState> {
  final Ref ref;

  ReaderNavigationNotifier(this.ref, int novelId)
    : super(ReaderNavigationState(novelId: novelId));

  Future<void> loadChapters(int startChapterId) async {
    try {
      final chapterDao = ref.read(chapterDaoProvider);
      final chapters = await chapterDao.getChaptersForNovel(state.novelId);
      final idx = chapters.indexWhere((c) => c.id == startChapterId);
      final index = idx < 0 ? 0 : idx;

      state = state.copyWith(
        chapters: chapters,
        currentIndex: index,
        isLoading: false,
      );

      _saveHistory();
      _loadCurrent();

      final chapter = state.currentChapter;
      if (chapter != null) {
        final position = await restoreReadingPosition(chapter.id);
        if (position != null) {
          ref.read(contentProvider.notifier).loadChapter(chapter.id).then((_) {
            ref
                .read(readerNavigationProvider(state.novelId).notifier)
                .setRestoredScrollPosition(position);
          });
        }
      }

      // Sync novel progress
      await _syncProgress();
    } catch (e) {
      Log.e(_tag, 'Failed to load chapters', e);
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load chapters',
      );
    }
  }

  Future<void> _saveHistory() async {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    final historyDao = ref.read(historyDaoProvider);
    await historyDao.addHistoryEntry(
      ReadingHistoryCompanion(
        novelId: Value(state.novelId),
        chapterId: Value(chapter.id),
        readAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );

    // Mark chapter as read
    await _markChapterAsRead(chapter.id);
  }

  Future<void> _markChapterAsRead(int chapterId) async {
    final chapterDao = ref.read(chapterDaoProvider);
    await chapterDao.markChapterAsRead(chapterId);
  }

  Future<void> _markChapterAsTtsRead(int chapterId) async {
    final chapterDao = ref.read(chapterDaoProvider);
    await chapterDao.markChapterAsTtsRead(chapterId);
  }

  Future<void> _syncProgress() async {
    try {
      final progressDao = ref.read(novelProgressDaoProvider);
      await progressDao.syncProgress(state.novelId);
    } catch (e) {
      Log.e(_tag, 'Failed to sync progress', e);
    }
  }

  Future<void> saveReadingPosition(double scrollProgress) async {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    final historyDao = ref.read(historyDaoProvider);
    await historyDao.addHistoryEntry(
      ReadingHistoryCompanion(
        novelId: Value(state.novelId),
        chapterId: Value(chapter.id),
        readAt: Value(DateTime.now().millisecondsSinceEpoch),
        scrollPosition: Value(scrollProgress),
      ),
    );
  }

  Future<double?> restoreReadingPosition(int chapterId) async {
    final historyDao = ref.read(historyDaoProvider);
    final latest = await historyDao.getLatestHistoryForNovel(state.novelId);
    if (latest == null || latest.scrollPosition == null) return null;
    if (latest.chapterId != chapterId) return null;
    return latest.scrollPosition;
  }

  bool get isFirstChapter => state.currentIndex <= 0;
  bool get isLastChapter => state.currentIndex >= state.chapters.length - 1;

  void goToPreviousChapter() {
    if (state.currentIndex <= 0) return;
    state = state.copyWith(currentIndex: state.currentIndex - 1);
    _saveHistory();
    _loadCurrent();
  }

  void goToNextChapter() {
    if (state.currentIndex >= state.chapters.length - 1) return;
    state = state.copyWith(currentIndex: state.currentIndex + 1);
    _saveHistory();
    _loadCurrent();
  }

  void jumpToChapter(int index) {
    if (index < 0 || index >= state.chapters.length) return;
    state = state.copyWith(currentIndex: index);
    _saveHistory();
    _loadCurrent();
  }

  void _loadCurrent() {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    ref.read(contentProvider.notifier).loadChapter(chapter.id);
    ref
        .read(contentProvider.notifier)
        .preloadSurrounding(chapter.id, state.chapters);
  }

  void setRestoredScrollPosition(double position) {
    state = state.copyWith(restoredScrollPosition: position);
  }

  void clearRestoredScrollPosition() {
    state = state.copyWith(restoredScrollPosition: null);
  }
}

final readerNavigationProvider =
    StateNotifierProvider.family<
      ReaderNavigationNotifier,
      ReaderNavigationState,
      int
    >((ref, novelId) {
      return ReaderNavigationNotifier(ref, novelId);
    });
