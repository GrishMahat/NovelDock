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
    test('insert/get/update round-trip', () async {
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
    });
  });

  group('LibraryDao', () {
    test('add/status/in-library/remove round-trip', () async {
      final id = await seedNovel();
      expect(await db.libraryDao.isInLibrary(id), isFalse);

      await db.libraryDao.addToLibrary(id, status: 'Reading');
      expect(await db.libraryDao.isInLibrary(id), isTrue);

      await db.libraryDao.updateStatus(id, 'Completed');
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
    });
  });

  group('DownloadDao', () {
    test('enqueue/status/claim/count/requeue lifecycle', () async {
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

    test('re-adding the same position returns the existing row', () async {
      final novelId = await seedNovel();
      final ch = await seedChapter(novelId);

      BookmarksCompanion bm(String note, int at) => BookmarksCompanion.insert(
        novelId: novelId,
        chapterId: ch,
        position: const Value('0.5000'),
        note: Value(note),
        createdAt: at,
      );

      final firstId = await db.bookmarkDao.addBookmark(bm('one', 1));
      // Double-tap / backup re-import: same (novel, chapter, position).
      final secondId = await db.bookmarkDao.addBookmark(bm('two', 2));

      expect(secondId, firstId);
      expect(await db.bookmarkDao.getBookmarksForChapter(ch), hasLength(1));
    });
  });

  group('SettingsDao', () {
    test('set/get/all round-trip', () async {
      await db.settingsDao.setSetting('k1', 'v1');
      await db.settingsDao.setSetting('k2', 'v2');
      expect(await db.settingsDao.getSetting('k1'), 'v1');
      expect(await db.settingsDao.getAllSettings(), {'k1': 'v1', 'k2': 'v2'});
    });
  });

  group('NovelProgressDao', () {
    test('updateProgress stores chapter totals', () async {
      final novelId = await seedNovel();

      await db.novelProgressDao.updateProgress(
        novelId: novelId,
        totalChapters: 10,
      );
      expect(
        (await db.novelProgressDao.getProgress(novelId))?.totalChapters,
        10,
      );
    });
  });
}
