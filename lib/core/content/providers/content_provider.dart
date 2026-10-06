import 'package:drift/drift.dart' show Value;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/utils/logger.dart';
import '../content_model.dart';
import '../loaders/content_loader.dart';
import '../loaders/downloaded_loader.dart';
import '../loaders/loader_selector.dart';

part 'content_provider.g.dart';

const _tag = 'ContentProvider';

class ContentState {
  final Map<int, AsyncValue<ChapterContent>> chapters;

  const ContentState({
    this.chapters = const <int, AsyncValue<ChapterContent>>{},
  });

  ContentState copyWith({Map<int, AsyncValue<ChapterContent>>? chapters}) {
    return ContentState(chapters: chapters ?? this.chapters);
  }
}

@Riverpod(keepAlive: true)
class ContentNotifier extends _$ContentNotifier {
  final Set<int> _loading = {};
  final LoaderSelector _selector = LoaderSelector();

  @override
  ContentState build() => const ContentState();

  Future<void> loadChapter(int chapterId) async {
    // A stored AsyncError must not block retry: the reader's Retry button
    // calls loadChapter for the same id, so only a cached success (or an
    // in-flight load) short-circuits here.
    final existing = state.chapters[chapterId];
    if (existing is AsyncData<ChapterContent>) return;
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

      state = state.copyWith(
        chapters: {...state.chapters, chapterId: AsyncValue.data(content)},
      );
    } catch (e, st) {
      Log.e(_tag, 'Failed to load chapter $chapterId', e);
      state = state.copyWith(
        chapters: {...state.chapters, chapterId: AsyncValue.error(e, st)},
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
    state = state.copyWith(chapters: {});
  }
}
