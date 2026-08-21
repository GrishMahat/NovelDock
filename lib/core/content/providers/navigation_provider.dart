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

  /// Block index within the current chapter to scroll to once content is
  /// built (cold-start resume). Consumed by the reader screen, then cleared.
  final int? restoredBlockIndex;

  const ReaderNavigationState({
    this.chapters = const <Chapter>[],
    this.currentIndex = 0,
    this.isLoading = true,
    this.error,
    required this.novelId,
    this.restoredBlockIndex,
  });

  ReaderNavigationState copyWith({
    List<Chapter>? chapters,
    int? currentIndex,
    bool? isLoading,
    String? error,
  }) {
    return ReaderNavigationState(
      chapters: chapters ?? this.chapters,
      currentIndex: currentIndex ?? this.currentIndex,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      novelId: novelId,
      restoredBlockIndex: restoredBlockIndex,
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

      // Read the previous session's anchor BEFORE writing a fresh history
      // entry, otherwise the new row shadows the saved position.
      final chapter = state.currentChapter;
      final blockIndex = chapter != null
          ? await restoreReadingAnchor(chapter.id)
          : null;

      _saveHistory();
      _loadCurrent();

      if (chapter != null && blockIndex != null) {
        ref.read(contentProvider.notifier).loadChapter(chapter.id).then((_) {
          // Direct call: reading our own provider here would be a
          // self-dependency.
          setRestoredBlockIndex(blockIndex);
        });
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
  }

  Future<void> _markChapterAsRead(int chapterId) async {
    final chapterDao = ref.read(chapterDaoProvider);
    await chapterDao.markChapterAsRead(chapterId);
  }

  Future<void> _syncProgress() async {
    try {
      final progressDao = ref.read(novelProgressDaoProvider);
      await progressDao.syncProgress(state.novelId);
    } catch (e) {
      Log.e(_tag, 'Failed to sync progress', e);
    }
  }

  /// Saves the reader anchor for the current chapter: the index of the
  /// content block currently at the top of the viewport. Stored in the
  /// history's scrollPosition column as blockIndex (>= 1). Block anchors
  /// survive lazy loading; raw scroll fractions do not.
  Future<void> saveReadingAnchor(int chapterId, int blockIndex) async {
    if (blockIndex < 0) return;
    final historyDao = ref.read(historyDaoProvider);
    await historyDao.addHistoryEntry(
      ReadingHistoryCompanion(
        novelId: Value(state.novelId),
        chapterId: Value(chapterId),
        readAt: Value(DateTime.now().millisecondsSinceEpoch),
        scrollPosition: Value(blockIndex.toDouble()),
      ),
    );
  }

  /// Returns the saved block anchor for [chapterId], or null when the latest
  /// history entry is for another chapter, has no anchor, or predates the
  /// block-anchor format (legacy values are fractions < 1).
  Future<int?> restoreReadingAnchor(int chapterId) async {
    final historyDao = ref.read(historyDaoProvider);
    final latest = await historyDao.getLatestHistoryForNovel(state.novelId);
    final pos = latest?.scrollPosition;
    if (latest == null || pos == null) return null;
    if (latest.chapterId != chapterId) return null;
    if (pos < 1) return null;
    return pos.floor();
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
    // Advancing past a chapter means it was read to the end.
    _markChapterAsRead(state.chapters[state.currentIndex].id);
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

  /// Called by the reader's scroll-spy in continuous mode when the viewport
  /// moves into another chapter. Updates tracking only; never scrolls.
  void syncCurrentIndexFromScroll(int index) {
    if (index < 0 || index >= state.chapters.length) return;
    if (index == state.currentIndex) return;
    if (index > state.currentIndex) {
      // Chapters scrolled past count as read.
      _markChapterAsRead(state.chapters[state.currentIndex].id);
    }
    state = state.copyWith(currentIndex: index);
    _saveHistory();
  }

  void _loadCurrent() {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    ref.read(contentProvider.notifier).loadChapter(chapter.id);
    ref
        .read(contentProvider.notifier)
        .preloadSurrounding(chapter.id, state.chapters);
  }

  void setRestoredBlockIndex(int blockIndex) {
    state = ReaderNavigationState(
      chapters: state.chapters,
      currentIndex: state.currentIndex,
      isLoading: state.isLoading,
      error: state.error,
      novelId: state.novelId,
      restoredBlockIndex: blockIndex,
    );
  }

  void clearRestoredBlockIndex() {
    state = ReaderNavigationState(
      chapters: state.chapters,
      currentIndex: state.currentIndex,
      isLoading: state.isLoading,
      error: state.error,
      novelId: state.novelId,
    );
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
