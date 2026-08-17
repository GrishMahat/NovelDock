import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;

import '../database/database.dart';
import 'database_providers.dart';
import '../network/client.dart';
import '../utils/logger.dart';
import 'engine.dart';

const _tag = 'NovelOpener';

/// Shared logic for opening a search/browse result as a novel:
/// inserts it into the DB, navigates to the detail screen, then fetches
/// novel info + chapter list in the background.
class NovelOpener {
  final WidgetRef ref;

  NovelOpener(this.ref);

  /// Insert the novel into the DB and return its row id.
  Future<int> insertNovel(SearchResultItem item) async {
    final novelDao = ref.read(novelDaoProvider);
    return novelDao.insertOrGetNovel(
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
    final id = await insertNovel(item);
    if (id > 0) {
      fetchNovelDetails(id, item);
    }
    return id;
  }

  /// Fetch novel details and chapters in the background.
  Future<void> fetchNovelDetails(int id, SearchResultItem item) async {
    try {
      final instance = await loadProviderById(item.providerId!, ref.container);
      if (instance == null) return;
      final novelDao = ref.read(novelDaoProvider);
      final chapterDao = ref.read(chapterDaoProvider);

      final novelUrl = await instance.getNovelInfoUrl(item.url);
      if (novelUrl == null) return;

      final dio = await ref.read(dioProvider.future);
      final response = await dio.get(novelUrl);
      final info = await instance.parseNovelInfo(response.data.toString());
      if (info == null) return;

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
          addedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

      final bookId = item.url.split('/').last.split('.').first;
      final chapterList = <ChaptersCompanion>[];
      if (info.chapters.isEmpty && bookId.isNotEmpty) {
        var page = 0;
        var chapterIndex = 0;
        while (true) {
          final chaptersUrl = await instance.call('getChaptersApiUrl', [
            bookId,
            page,
          ]);
          if (chaptersUrl == null || chaptersUrl is! String) break;
          final chResponse = await dio.get(chaptersUrl);
          final chHtml = chResponse.data.toString();
          if (chHtml.trim().isEmpty) break;
          final chList = await instance.call('parseChapterList', [chHtml]);
          if (chList == null || chList is! List || chList.isEmpty) break;
          for (var i = 0; i < chList.length; i++) {
            final ch = chList[i] as Map<String, dynamic>;
            chapterList.add(
              ChaptersCompanion(
                novelId: Value(id),
                name: Value(ch['name'] as String? ?? ''),
                url: Value(ch['url'] as String? ?? ''),
                index: Value(chapterIndex.toDouble()),
              ),
            );
            chapterIndex++;
          }
          page++;
        }
      } else {
        for (var i = 0; i < info.chapters.length; i++) {
          final ch = info.chapters[i];
          chapterList.add(
            ChaptersCompanion(
              novelId: Value(id),
              name: Value(ch.name),
              url: Value(ch.url),
              index: Value(i.toDouble()),
            ),
          );
        }
      }
      await chapterDao.insertChaptersForNovel(id, chapterList);
    } catch (e) {
      Log.w(_tag, 'Failed to fetch novel details: $e');
    }
  }
}