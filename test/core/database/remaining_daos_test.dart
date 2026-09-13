import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> seedNovel({String url = 'https://example.com/novel/1'}) {
    return db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            providerId: 'test',
            url: url,
            title: 'Test Novel',
            addedAt: 1,
          ),
        );
  }

  Future<int> seedChapter(int novelId, {String url = 'c1'}) {
    return db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            novelId: novelId,
            name: 'Chapter 1',
            url: url,
            index: 0,
          ),
        );
  }

  group('NovelDao', () {
    test('insert/get/update/delete round-trip', () async {
      final id = await seedNovel();
      expect((await db.novelDao.getNovelById(id))?.title, 'Test Novel');
      expect(
        (await db.novelDao.getNovelByUrl('https://example.com/novel/1'))?.id,
        id,
      );

      await db.novelDao.updateNovel(
        NovelsCompanion(id: Value(id), title: const Value('Renamed')),
      );
      expect((await db.novelDao.getNovelById(id))?.title, 'Renamed');

      expect(await db.novelDao.searchNovels('Renam'), hasLength(1));
      expect(await db.novelDao.searchNovels('zzz-no-match'), isEmpty);

      await db.novelDao.deleteNovel(id);
      expect(await db.novelDao.getNovelById(id), isNull);
    });

    test('insertOrGetNovel returns existing row', () async {
      final first = await db.novelDao.insertOrGetNovel(
        providerId: 'test',
        url: 'https://example.com/dedupe',
        title: 'Dedupe',
      );
      final second = await db.novelDao.insertOrGetNovel(
        providerId: 'test',
        url: 'https://example.com/dedupe',
        title: 'Dedupe',
      );
      expect(first, second);
      expect(await db.novelDao.getAllNovels(), hasLength(1));
    });
  });

  group('LibraryDao', () {
    test('add/status/in-library/remove round-trip', () async {
      final id = await seedNovel();
      expect(await db.libraryDao.isInLibrary(id), isFalse);

      await db.libraryDao.addToLibrary(id, status: 'Reading');
      expect(await db.libraryDao.isInLibrary(id), isTrue);

      await db.libraryDao.updateStatus(id, 'Completed');
      final novels = await db.libraryDao.getLibraryNovels();
      expect(novels, hasLength(1));

      final byStatus = await db.libraryDao
          .watchLibraryNovelsByStatus('Completed')
          .first;
      expect(byStatus, hasLength(1));

      expect(await db.libraryDao.removeFromLibrary(id), isTrue);
      expect(await db.libraryDao.isInLibrary(id), isFalse);
    });
  });

  group('HistoryDao', () {
    test('one row per novel: reopen updates instead of duplicating', () async {
      final novelId = await seedNovel();
      final ch1 = await seedChapter(novelId, url: 'c1');
      final ch2 = await seedChapter(novelId, url: 'c2');

      await db.historyDao.addHistoryEntry(
        ReadingHistoryCompanion.insert(
          novelId: novelId,
          chapterId: ch1,
          readAt: 100,
        ),
      );
      await db.historyDao.addHistoryEntry(
        ReadingHistoryCompanion.insert(
          novelId: novelId,
          chapterId: ch2,
          readAt: 200,
        ),
      );

      final all = await db.historyDao.getAllHistory();
      expect(all, hasLength(1));
      expect(all.first.chapterId, ch2);
      expect(
        (await db.historyDao.getLatestHistoryForNovel(novelId))?.chapterId,
        ch2,
      );

      await db.historyDao.clearHistoryForNovel(novelId);
      expect(await db.historyDao.getAllHistory(), isEmpty);
    });
  });

  group('DownloadDao', () {
    test('enqueue/status/claim/count/requeue/clear lifecycle', () async {
      final novelId = await seedNovel();
      final ch = await seedChapter(novelId);

      final id = await db.downloadDao.enqueueDownload(
        DownloadsQueueCompanion.insert(
          novelId: novelId,
          chapterId: ch,
          status: 'queued',
        ),
      );
      expect((await db.downloadDao.getDownloadById(id))?.status, 'queued');

      final claimed = await db.downloadDao.claimNextQueued();
      expect(claimed?.id, id);

      final counts = await db.downloadDao.countByStatus(novelId);
      expect(counts['downloading'], 1);

      expect(await db.downloadDao.requeueStaleDownloading(), 1);
      expect((await db.downloadDao.getDownloadById(id))?.status, 'queued');

      await db.downloadDao.updateDownloadStatus(id, 'done', progress: 1.0);
      await db.downloadDao.clearCompletedDownloads();
      expect(await db.downloadDao.getAllDownloads(), isEmpty);
    });
  });

  group('BookmarkDao', () {
    test('add/list-by-chapter/remove round-trip', () async {
      final novelId = await seedNovel();
      final ch = await seedChapter(novelId);

      await db.bookmarkDao.addBookmark(
        BookmarksCompanion.insert(
          novelId: novelId,
          chapterId: ch,
          createdAt: 1,
        ),
      );
      await db.bookmarkDao.addBookmark(
        BookmarksCompanion.insert(
          novelId: novelId,
          chapterId: ch,
          createdAt: 2,
        ),
      );
      expect(await db.bookmarkDao.getBookmarksForChapter(ch), hasLength(2));
      expect(await db.bookmarkDao.getBookmarksForNovel(novelId), hasLength(2));

      final first = (await db.bookmarkDao.getBookmarksForChapter(ch)).first;
      await db.bookmarkDao.removeBookmark(first.id);
      expect(await db.bookmarkDao.getBookmarksForChapter(ch), hasLength(1));
    });
  });

  group('SettingsDao', () {
    test('set/get/delete/all round-trip', () async {
      await db.settingsDao.setSetting('k1', 'v1');
      await db.settingsDao.setSetting('k2', 'v2');
      expect(await db.settingsDao.getSetting('k1'), 'v1');
      expect(
        await db.settingsDao.getSettingOrDefault('missing', 'dflt'),
        'dflt',
      );
      expect(await db.settingsDao.getAllSettings(), {'k1': 'v1', 'k2': 'v2'});

      await db.settingsDao.deleteSetting('k1');
      expect(await db.settingsDao.getSetting('k1'), isNull);
    });
  });

  group('NovelProgressDao', () {
    test('upsert then increment tracks read chapters', () async {
      final novelId = await seedNovel();
      final ch = await seedChapter(novelId);

      await db.novelProgressDao.updateProgress(
        novelId: novelId,
        totalChapters: 10,
      );
      expect(
        (await db.novelProgressDao.getProgress(novelId))?.totalChapters,
        10,
      );

      await db.novelProgressDao.incrementReadChapters(novelId, ch);
      final progress = await db.novelProgressDao.getProgress(novelId);
      expect(progress?.readChapters, 1);
      expect(progress?.lastReadChapterId, ch);
    });
  });

  group('ProviderCacheDao', () {
    test('insert/get/enabled/delete round-trip', () async {
      await db.providerCacheDao.insertOrUpdateProvider(
        ProviderCacheCompanion.insert(
          id: 'wuxiabox',
          name: 'WuxiaBox',
          version: '1.0.0',
          jsSource: 'code',
          lastUpdated: 1,
        ),
      );
      expect(
        (await db.providerCacheDao.getProviderById('wuxiabox'))?.name,
        'WuxiaBox',
      );
      expect(await db.providerCacheDao.getEnabledProviders(), isEmpty);

      await db.providerCacheDao.updateProvider('wuxiabox', enabled: true);
      expect(await db.providerCacheDao.getEnabledProviders(), hasLength(1));

      await db.providerCacheDao.deleteProvider('wuxiabox');
      expect(await db.providerCacheDao.getAllProviders(), isEmpty);
    });
  });
}
