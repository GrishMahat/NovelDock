import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;

import '../database/database.dart';
import 'database_providers.dart';
import 'novel_fetch_state.dart';
import '../network/client.dart';
import '../utils/logger.dart';
import 'engine.dart';

const _tag = 'NovelOpener';

/// Shared logic for a novel's lifecycle:
/// - [open]: insert a search/browse result and fetch its details in the
///   background.
/// - [refreshNovel]: re-fetch info + chapter list for an existing novel
///   without resetting [Novels.addedAt].
/// - [firstChapterId]: entry chapter used by "play from start" actions.
///
/// Exposed via [novelOpenerProvider] so it always holds a provider-level
/// [Ref]; a widget-scoped ref would throw if the originating screen is
/// disposed while the background fetch is still running.
class NovelOpener {
  final Ref ref;

  NovelOpener(this.ref);

  /// Insert the novel into the DB and report whether the row was newly
  /// created (as opposed to an already-existing one).
  Future<(int, bool)> insertNovel(SearchResultItem item) async {
    final novelDao = ref.read(novelDaoProvider);
    return novelDao.insertOrGetNovelWithStatus(
      providerId: item.providerId!,
      url: item.url,
      title: item.title,
      author: item.author,
      coverUrl: item.cover,
    );
  }

  /// Insert the novel, kick off background detail/chapter fetch, and
  /// return the row id (caller navigates with it).
  Future<int> open(SearchResultItem item) async {
    Log.i(_tag, 'Opening: "${item.title}" from ${item.providerId}');
    if (item.providerId == null) {
      Log.e(_tag, 'No providerId, aborting');
      return -1;
    }
    final (id, isNew) = await insertNovel(item);
    if (id > 0) {
      // Skip the background re-fetch for novels that already have chapters:
      // re-opening an existing novel must not clobber refreshed metadata
      // with search-listing data. "Refresh" on the detail screen does that
      // explicitly. Re-fetch only when the novel is new or has no chapters
      // (e.g. a previous fetch failed or is still incomplete).
      final chapterCount = await ref
          .read(chapterDaoProvider)
          .getChapterCount(id);
      if (isNew || chapterCount == 0) {
        fetchNovelDetails(id, item, isNew: isNew);
      }
    }
    return id;
  }

  /// Fetch novel details and chapters in the background.
  Future<void> fetchNovelDetails(
    int id,
    SearchResultItem item, {
    bool isNew = false,
  }) async {
    final phase = ref.read(novelFetchStateProvider(id).notifier);
    phase.set(NovelFetchPhase.fetchingInfo);
    try {
      final instance = await ref.read(
        providerInstanceProvider(item.providerId!).future,
      );
      if (instance == null) {
        phase.set(NovelFetchPhase.failed);
        return;
      }
      final novelDao = ref.read(novelDaoProvider);

      final novelUrl = await instance.getNovelInfoUrl(item.url);
      if (novelUrl == null) {
        phase.set(NovelFetchPhase.failed);
        return;
      }

      final dio = await ref.read(dioProvider.future);
      final response = await dio.get(novelUrl);
      final info = await instance.parseNovelInfo(response.data.toString());
      if (info == null) {
        phase.set(NovelFetchPhase.failed);
        return;
      }

      await novelDao.updateNovel(
        NovelsCompanion(
          id: Value(id),
          providerId: Value(item.providerId!),
          url: Value(item.url),
          title: Value(item.title),
          author: Value(item.author ?? info.author),
          coverUrl: Value(item.cover ?? info.cover),
          description: Value(info.description),
          genres: Value(info.genres.join(',')),
          status: Value(info.status),
          addedAt: isNew
              ? Value(DateTime.now().millisecondsSinceEpoch)
              : const Value.absent(),
        ),
      );

      phase.set(NovelFetchPhase.fetchingChapters);
      await _insertChapters(instance, id, item.url, info.chapters, dio);
      phase.set(NovelFetchPhase.completed);
    } catch (e) {
      Log.w(_tag, 'Failed to fetch novel details: $e');
      phase.set(NovelFetchPhase.failed);
    }
  }

  /// Re-fetch info + chapters for an existing novel. Unlike
  /// [fetchNovelDetails], [Novels.addedAt] is preserved. Refreshing must
  /// not reset the date the novel was added to the library.
  /// Returns false when the novel or its provider is unavailable.
  Future<bool> refreshNovel(int novelId) async {
    final phase = ref.read(novelFetchStateProvider(novelId).notifier);
    phase.set(NovelFetchPhase.fetchingInfo);
    try {
      final novelDao = ref.read(novelDaoProvider);
      final novel = await novelDao.getNovelById(novelId);
      if (novel == null) return false;

      final instance = await ref.read(
        providerInstanceProvider(novel.providerId).future,
      );
      if (instance == null) {
        phase.set(NovelFetchPhase.failed);
        return false;
      }

      final novelUrl = await instance.getNovelInfoUrl(novel.url);
      if (novelUrl == null) {
        phase.set(NovelFetchPhase.failed);
        return false;
      }

      final dio = await ref.read(dioProvider.future);
      final response = await dio.get(novelUrl);
      final info = await instance.parseNovelInfo(response.data.toString());
      if (info == null) {
        phase.set(NovelFetchPhase.failed);
        return false;
      }

      await novelDao.updateNovel(
        NovelsCompanion(
          id: Value(novelId),
          providerId: Value(novel.providerId),
          url: Value(novel.url),
          title: Value(info.title),
          author: Value(info.author),
          coverUrl: Value(info.cover ?? novel.coverUrl),
          description: Value(info.description),
          genres: Value(info.genres.join(',')),
          status: Value(info.status),
        ),
      );

      phase.set(NovelFetchPhase.fetchingChapters);
      await _insertChapters(instance, novelId, novel.url, info.chapters, dio);
      phase.set(NovelFetchPhase.completed);
      return true;
    } catch (e) {
      Log.w(_tag, 'Failed to refresh novel $novelId: $e');
      phase.set(NovelFetchPhase.failed);
      return false;
    }
  }

  /// Chapter id of the novel's first chapter, or null if it has none.
  Future<int?> firstChapterId(int novelId) async {
    final chapterDao = ref.read(chapterDaoProvider);
    final chapters = await chapterDao.getChaptersForNovel(novelId);
    if (chapters.isEmpty) return null;
    return chapters.first.id;
  }

  /// Build and store the chapter list for a novel. Falls back to the
  /// provider's paginated chapter API when the parsed novel info carries
  /// no chapters (e.g. LightNovels/ScribbleHub style listings).
  Future<void> _insertChapters(
    ProviderInstance instance,
    int novelId,
    String novelUrl,
    List<NovelChapter> chapters,
    Dio dio,
  ) async {
    final chapterDao = ref.read(chapterDaoProvider);

    final bookId = novelUrl.split('/').last.split('.').first;
    final chapterList = <ChaptersCompanion>[];
    try {
      if (chapters.isEmpty && bookId.isNotEmpty) {
        // Hard caps so a misbehaving provider (e.g. one that ignores the
        // `page` parameter) can't loop forever or fill the DB with
        // duplicates. A page that adds no new chapter URLs ends the walk.
        const maxChapterApiPages = 500;
        final seenChapterUrls = <String>{};
        var page = 0;
        var chapterIndex = 0;
        while (page < maxChapterApiPages) {
          final config = instance.hasFunction('getChaptersApiConfig')
              ? await instance.call('getChaptersApiConfig', [bookId, page])
              : null;
          Object? chData;
          if (config is Map<String, dynamic> &&
              config['url'] is String &&
              config['body'] is List) {
            final headers =
                (config['headers'] as Map<String, dynamic>?)?.map(
                  (k, v) => MapEntry(k, v.toString()),
                ) ??
                const <String, String>{};
            final chResponse = await dio.post(
              config['url'] as String,
              data: Uint8List.fromList((config['body'] as List).cast<int>()),
              options: Options(
                headers: headers,
                responseType: ResponseType.bytes,
                followRedirects: false,
                validateStatus: (status) => status != null && status < 500,
              ),
            );
            if (chResponse.statusCode != 200) break;
            chData = chResponse.data;
          } else {
            if (!instance.hasFunction('getChaptersApiUrl')) break;
            final chaptersUrl = await instance.call('getChaptersApiUrl', [
              bookId,
              page,
            ]);
            if (chaptersUrl == null || chaptersUrl is! String) break;
            final chResponse = await dio.get(
              chaptersUrl,
              options: Options(
                // Tolerate non-2xx (e.g. Syosetu answers 404 one page past
                // the last chapter list) so the loop ends cleanly instead of
                // aborting chapter insertion with a DioException.
                validateStatus: (status) => status != null && status < 500,
                responseType: ResponseType.plain,
              ),
            );
            if (chResponse.statusCode != 200) break;
            chData = chResponse.data.toString();
            if ((chData as String).trim().isEmpty) break;
          }
          final chList = await instance.call('parseChapterList', [chData]);
          if (chList == null || chList is! List || chList.isEmpty) break;
          var addedThisPage = 0;
          for (var i = 0; i < chList.length; i++) {
            final ch = chList[i] as Map<String, dynamic>;
            final url = ch['url'] as String? ?? '';
            // Skip empty URLs and anything already seen on an earlier page.
            if (url.isEmpty || !seenChapterUrls.add(url)) continue;
            chapterList.add(
              ChaptersCompanion(
                novelId: Value(novelId),
                name: Value(ch['name'] as String? ?? ''),
                url: Value(url),
                index: Value(chapterIndex.toDouble()),
              ),
            );
            chapterIndex++;
            addedThisPage++;
          }
          page++;
          // Same page returned twice — the site ignored the page parameter.
          if (addedThisPage == 0) break;
        }
        if (page >= maxChapterApiPages) {
          Log.w(
            _tag,
            'Chapter API pagination hit the $maxChapterApiPages page cap '
            'for $novelUrl',
          );
        }
      } else {
        for (var i = 0; i < chapters.length; i++) {
          final ch = chapters[i];
          chapterList.add(
            ChaptersCompanion(
              novelId: Value(novelId),
              name: Value(ch.name),
              url: Value(ch.url),
              index: Value(i.toDouble()),
            ),
          );
        }
      }
    } catch (e) {
      Log.w(_tag, 'Failed to fetch novel details: $e');
    }
    await chapterDao.syncChaptersForNovel(novelId, chapterList);
  }
}

/// Provider-scoped [NovelOpener]. Use `ref.read(novelOpenerProvider)` from
/// widgets instead of constructing one with a [WidgetRef] — the background
/// fetch outlives the originating screen.
final novelOpenerProvider = Provider<NovelOpener>((ref) => NovelOpener(ref));
