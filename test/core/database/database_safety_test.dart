import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/database/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

// Data-safety pin tests. Each one covers a live data-loss path found in
// audit: stale-sync dependent cleanup, the settings single-row invariant,
// the v1->v3 migration, continue-reading semantics, and idempotent novel
// insert. If any of these fail, user data is being destroyed.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> seedNovel() {
    return db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            providerId: 'test',
            url: 'https://example.com/novel/1',
            title: 'Test Novel',
            addedAt: 12345,
          ),
        );
  }

  List<ChaptersCompanion> chaptersFor(int novelId, List<String> urls) => [
    for (var i = 0; i < urls.length; i++)
      ChaptersCompanion.insert(
        novelId: novelId,
        name: 'Chapter $i',
        url: urls[i],
        index: i.toDouble(),
      ),
  ];

  group('syncChaptersForNovel dependent cleanup', () {
    test(
      'vanished chapters take their history/queue/bookmarks/anchors',
      () async {
        final novelId = await seedNovel();
        await db.chapterDao.syncChaptersForNovel(
          novelId,
          chaptersFor(novelId, ['a', 'b', 'c']),
        );
        final rows = await db.chapterDao.getChaptersForNovel(novelId);
        final chapterA = rows.firstWhere((r) => r.url == 'a');

        // Accumulate state keyed by chapter A, as the reader/downloads do.
        await db.historyDao.addHistoryEntry(
          ReadingHistoryCompanion.insert(
            novelId: novelId,
            chapterId: chapterA.id,
            readAt: 1,
          ),
        );
        await db.bookmarkDao.addBookmark(
          BookmarksCompanion.insert(
            novelId: novelId,
            chapterId: chapterA.id,
            createdAt: 1,
          ),
        );
        await db.downloadDao.enqueueDownload(
          DownloadsQueueCompanion.insert(
            novelId: novelId,
            chapterId: chapterA.id,
            status: 'done',
          ),
        );
        await db.libraryDao.addToLibrary(novelId);
        await (db.update(db.library)..where((t) => t.novelId.equals(novelId)))
            .write(LibraryCompanion(lastChapterId: Value(chapterA.id)));
        await db.novelProgressDao.updateProgress(
          novelId: novelId,
          totalChapters: 3,
          lastReadChapterId: chapterA.id,
          lastTtsChapterId: chapterA.id,
        );

        // Full server list without 'a': 'a' vanished legitimately.
        await db.chapterDao.syncChaptersForNovel(
          novelId,
          chaptersFor(novelId, ['b', 'c']),
        );

        expect(
          (await db.chapterDao.getChaptersForNovel(novelId)).map((r) => r.url),
          ['b', 'c'],
        );
        // Survivors keep identity.
        final bAfter = (await db.chapterDao.getChaptersForNovel(
          novelId,
        )).firstWhere((r) => r.url == 'b');
        expect(bAfter.id, rows.firstWhere((r) => r.url == 'b').id);
        // Dependents of the vanished chapter are gone, not dangling.
        expect(await db.historyDao.getHistoryForNovel(novelId), isEmpty);
        expect(await db.bookmarkDao.getBookmarksForNovel(novelId), isEmpty);
        expect(await db.downloadDao.getPendingDownloads(), isEmpty);
        final entry = await (db.select(
          db.library,
        )..where((t) => t.novelId.equals(novelId))).getSingle();
        expect(entry.lastChapterId, isNull);
        final progress = await db.novelProgressDao.getProgress(novelId);
        expect(progress!.lastReadChapterId, isNull);
        expect(progress.lastTtsChapterId, isNull);
      },
    );
  });

  group('settings single-row invariant', () {
    test('setSetting twice keeps one row with the latest value', () async {
      await db.settingsDao.setSetting('k', 'v1');
      await db.settingsDao.setSetting('k', 'v2');
      expect(await db.settingsDao.getSetting('k'), 'v2');
      final count = await db
          .customSelect('SELECT COUNT(*) AS c FROM settings')
          .map((row) => row.read<int>('c'))
          .getSingle();
      expect(count, 1);
    });
  });

  group('continue reading', () {
    test('includes novels with unread chapters past the anchor only', () async {
      Future<int> seed(String url) => db
          .into(db.novels)
          .insert(
            NovelsCompanion.insert(
              providerId: 't',
              url: url,
              title: url,
              addedAt: 1,
            ),
          );

      // Novel 1: anchor at ch0, ch1 unread -> included.
      final n1 = await seed('n1');
      await db.chapterDao.syncChaptersForNovel(n1, chaptersFor(n1, ['a', 'b']));
      final ch0 = (await db.chapterDao.getChaptersForNovel(n1)).first;
      await db.chapterDao.markChapterAsRead(ch0.id);
      await db.libraryDao.addToLibrary(n1);
      await (db.update(db.library)..where((t) => t.novelId.equals(n1))).write(
        LibraryCompanion(lastChapterId: Value(ch0.id)),
      );

      // Novel 2: everything read -> excluded.
      final n2 = await seed('n2');
      await db.chapterDao.syncChaptersForNovel(n2, chaptersFor(n2, ['a']));
      final n2ch = (await db.chapterDao.getChaptersForNovel(n2)).first;
      await db.chapterDao.markChapterAsRead(n2ch.id);
      await db.libraryDao.addToLibrary(n2);
      await (db.update(db.library)..where((t) => t.novelId.equals(n2))).write(
        LibraryCompanion(lastChapterId: Value(n2ch.id)),
      );

      // Novel 3: in library but no anchor -> excluded.
      final n3 = await seed('n3');
      await db.chapterDao.syncChaptersForNovel(n3, chaptersFor(n3, ['a', 'b']));
      await db.libraryDao.addToLibrary(n3);

      final result = await db.libraryDao.getContinueReadingNovels();
      expect(result.map((n) => n.url), ['n1']);
    });
  });

  group('novel insert idempotence', () {
    test('insertOrGetNovel twice returns one row', () async {
      final first = await db.novelDao.insertOrGetNovel(
        providerId: 'p',
        url: 'u',
        title: 't',
      );
      final second = await db.novelDao.insertOrGetNovel(
        providerId: 'p',
        url: 'u',
        title: 't',
      );
      expect(first, second);
      expect(await db.novelDao.getAllNovels(), hasLength(1));
    });

    test('insertOrGetNovelWithStatus reports creation exactly once', () async {
      final (id1, created1) = await db.novelDao.insertOrGetNovelWithStatus(
        providerId: 'p',
        url: 'u2',
        title: 't',
      );
      final (id2, created2) = await db.novelDao.insertOrGetNovelWithStatus(
        providerId: 'p',
        url: 'u2',
        title: 't',
      );
      expect(id1, id2);
      expect(created1, isTrue);
      expect(created2, isFalse);
    });
  });

  group('migration v1 -> v3', () {
    test('legacy database upgrades with data intact', () async {
      final dir = await Directory.systemTemp.createTemp('noveldock-mig');
      final path = '${dir.path}/v1.sqlite';
      try {
        // Minimal v1 layout: no tts_read/bookmarked, no novel_progress.
        final raw = sqlite.sqlite3.open(path);
        raw.execute(
          'CREATE TABLE novels (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'provider_id TEXT NOT NULL, url TEXT NOT NULL UNIQUE, '
          'title TEXT NOT NULL, author TEXT, cover_url TEXT, '
          'description TEXT, genres TEXT, status TEXT, '
          'added_at INTEGER NOT NULL)',
        );
        raw.execute(
          'CREATE TABLE chapters (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'novel_id INTEGER NOT NULL, name TEXT NOT NULL, url TEXT NOT NULL, '
          '"index" REAL NOT NULL, downloaded INTEGER NOT NULL DEFAULT 0, '
          'read INTEGER NOT NULL DEFAULT 0, downloaded_path TEXT, '
          'UNIQUE(novel_id, url))',
        );
        raw.execute(
          'CREATE TABLE settings ("key" TEXT NOT NULL, value TEXT NOT NULL)',
        );
        raw.execute(
          'CREATE TABLE reading_history (id INTEGER PRIMARY KEY '
          'AUTOINCREMENT, novel_id INTEGER NOT NULL, chapter_id INTEGER '
          'NOT NULL, read_at INTEGER NOT NULL, scroll_position REAL, '
          'progress REAL)',
        );
        raw.execute(
          'CREATE TABLE downloads_queue (id INTEGER PRIMARY KEY '
          'AUTOINCREMENT, novel_id INTEGER NOT NULL, chapter_id INTEGER '
          'NOT NULL, status TEXT NOT NULL, progress REAL, error TEXT)',
        );
        raw.execute(
          'CREATE TABLE bookmarks (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'novel_id INTEGER NOT NULL, chapter_id INTEGER NOT NULL, '
          'position TEXT, note TEXT, created_at INTEGER NOT NULL)',
        );
        raw.execute(
          'CREATE TABLE library (novel_id INTEGER NOT NULL, '
          'last_chapter_id INTEGER, last_read_at INTEGER, "order" INTEGER, '
          'status TEXT)',
        );
        raw.execute(
          'CREATE TABLE provider_cache (id TEXT NOT NULL, name TEXT NOT '
          'NULL, version TEXT NOT NULL, js_source TEXT NOT NULL, '
          'enabled INTEGER NOT NULL DEFAULT 0, last_updated INTEGER NOT NULL)',
        );
        raw.execute(
          "INSERT INTO novels (provider_id, url, title, added_at) VALUES "
          "('p', 'u', 't', 1)",
        );
        raw.execute(
          'INSERT INTO chapters (novel_id, name, url, "index") VALUES '
          "(1, 'c', 'cu', 0)",
        );
        // Duplicate settings key, as v1 allowed: migration must dedupe.
        raw.execute(
          "INSERT INTO settings (\"key\", value) VALUES ('k', 'old')",
        );
        raw.execute(
          "INSERT INTO settings (\"key\", value) VALUES ('k', 'new')",
        );
        raw.execute('PRAGMA user_version = 1');
        raw.close();

        final appDb = AppDatabase.withExecutor(NativeDatabase(File(path)));
        try {
          // Any query forces open + migration.
          final novels = await appDb.novelDao.getAllNovels();
          expect(novels, hasLength(1));
          expect(novels.first.title, 't');

          final cols = await appDb
              .customSelect('PRAGMA table_info(chapters)')
              .map((row) => row.read<String>('name'))
              .get();
          expect(cols, containsAll(['tts_read', 'bookmarked']));

          final tables = await appDb
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table'",
              )
              .map((row) => row.read<String>('name'))
              .get();
          expect(tables, contains('novel_progress'));

          final indexes = await appDb
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'",
              )
              .map((row) => row.read<String>('name'))
              .get();
          expect(
            indexes,
            containsAll([
              'settings_key_unique',
              'reading_history_novel',
              'downloads_queue_status',
              'bookmarks_novel_chapter',
              'chapters_novel_downloaded',
            ]),
          );

          // Latest duplicate wins, single row remains.
          expect(await appDb.settingsDao.getSetting('k'), 'new');

          final version = await appDb
              .customSelect('PRAGMA user_version')
              .map((row) => row.read<int>('user_version'))
              .getSingle();
          expect(version, 3);
        } finally {
          await appDb.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
