import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/utils/logger.dart';
import '../../../core/utils/lru_cache.dart';
import '../content_model.dart';
import '../loaders/content_loader.dart';
import '../loaders/downloaded_loader.dart';
import '../loaders/loader_selector.dart';

const _tag = 'ContentProvider';
const _maxCache = 20;

class ContentState {
  final Map<int, AsyncValue<ChapterContent>> chapters;
  final bool isLoading;
  final String? error;

  const ContentState({
    this.chapters = const <int, AsyncValue<ChapterContent>>{},
    this.isLoading = false,
    this.error,
  });

  ContentState copyWith({
    Map<int, AsyncValue<ChapterContent>>? chapters,
    bool? isLoading,
    Object? error,
  }) {
    return ContentState(
      chapters: chapters ?? this.chapters,
      isLoading: isLoading ?? this.isLoading,
      error: error is String? ? error : this.error,
    );
  }
}

class ContentNotifier extends StateNotifier<ContentState> {
  final Ref ref;
  final LruCache<int, ChapterContent> _cache = LruCache(_maxCache);
  final Set<int> _loading = {};
  final LoaderSelector _selector = LoaderSelector();

  ContentNotifier(this.ref) : super(const ContentState());

  Future<void> loadChapter(int chapterId) async {
    if (state.chapters.containsKey(chapterId)) return;
    if (_loading.contains(chapterId)) return;

    _loading.add(chapterId);

    try {
      final chapterDao = ref.read(chapterDaoProvider);
      final chapter = await chapterDao.getChapterById(chapterId);

      if (chapter == null) {
        throw Exception('Chapter $chapterId not found in database');
      }

      ContentLoader loader = _selector.select(chapter);

      ChapterContent content;
      try {
        content = await loader.load(chapter, ref);
      } on StaleDownloadException {
        // The DB says this chapter is downloaded but its file is gone.
        // Heal the flag and fall back to the remote source instead of
        // surfacing an error for content that is still reachable online.
        Log.w(_tag, 'Stale download for chapter $chapterId; refetching');
        await chapterDao.markNotDownloaded(chapterId);
        final healed = chapter.copyWith(downloadedPath: const Value(null));
        loader = _selector.select(healed);
        content = await loader.load(healed, ref);
      }

      _cache[chapterId] = content;

      state = state.copyWith(
        chapters: {...state.chapters, chapterId: AsyncValue.data(content)},
      );
    } catch (e, st) {
      Log.e(_tag, 'Failed to load chapter $chapterId', e);
      state = state.copyWith(
        chapters: {...state.chapters, chapterId: AsyncValue.error(e, st)},
        error: e.toString(),
      );
    } finally {
      _loading.remove(chapterId);
    }
  }

  void preloadSurrounding(int currentChapterId, List<Chapter> chapterList) {
    final index = chapterList.indexWhere((c) => c.id == currentChapterId);
    if (index < 0) return;

    for (final offset in [-3, -2, -1, 1, 2, 3]) {
      final i = index + offset;
      if (i >= 0 && i < chapterList.length) {
        final cid = chapterList[i].id;
        if (!state.chapters.containsKey(cid) && !_loading.contains(cid)) {
          loadChapter(cid);
        }
      }
    }
  }

  ChapterContent? getChapter(int chapterId) {
    final entry = state.chapters[chapterId];
    if (entry is AsyncData<ChapterContent>) return entry.value;
    return null;
  }

  String? getContentMd(int chapterId) {
    final content = getChapter(chapterId);
    if (content != null && content.format == ContentFormat.markdown) {
      return content.data;
    }
    return null;
  }

  void clearCache() {
    _cache.clear();
    state = state.copyWith(chapters: {});
  }
}

final contentProvider = StateNotifierProvider<ContentNotifier, ContentState>((
  ref,
) {
  return ContentNotifier(ref);
});
