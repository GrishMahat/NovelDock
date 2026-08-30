import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> seedNovel() async {
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

  // ChaptersCompanion.insert needs the novelId up front, so build with the
  // real id.
  List<ChaptersCompanion> chaptersFor(int novelId, List<String> urls) => [
    for (var i = 0; i < urls.length; i++)
      ChaptersCompanion.insert(
        novelId: novelId,
        name: 'Chapter $i',
        url: urls[i],
        index: i.toDouble(),
      ),
  ];

  test('initial sync inserts all chapters', () async {
    final novelId = await seedNovel();
    await db.chapterDao.syncChaptersForNovel(
      novelId,
      chaptersFor(novelId, ['a', 'b', 'c']),
    );

    final rows = await db.chapterDao.getChaptersForNovel(novelId);
    expect(rows.map((r) => r.url), ['a', 'b', 'c']);
    expect(rows.map((r) => r.index), [0.0, 1.0, 2.0]);
  });

  test(
    'refresh keeps chapter ids and per-chapter state for surviving URLs',
    () async {
      final novelId = await seedNovel();
      await db.chapterDao.syncChaptersForNovel(
        novelId,
        chaptersFor(novelId, ['a', 'b', 'c']),
      );

      final before = await db.chapterDao.getChaptersForNovel(novelId);
      final chapterB = before.firstWhere((r) => r.url == 'b');

      // Simulate reader state accumulated on 'b'.
      await db.chapterDao.markChapterAsRead(chapterB.id);
      await db.chapterDao.toggleBookmark(chapterB.id, true);
      await db.chapterDao.markChapterAsDownloaded(chapterB.id, '/tmp/b.md');

      // Source list changes: 'a' vanished, 'b' renamed, 'd' added.
      await db.chapterDao.syncChaptersForNovel(
        novelId,
        chaptersFor(novelId, ['b', 'c', 'd']),
      );

      final after = await db.chapterDao.getChaptersForNovel(novelId);
      expect(after.map((r) => r.url), ['b', 'c', 'd']);

      final chapterBAfter = after.firstWhere((r) => r.url == 'b');
      // Same row identity — references by chapter id survive.
      expect(chapterBAfter.id, chapterB.id);
      expect(chapterBAfter.read, isTrue);
      expect(chapterBAfter.bookmarked, isTrue);
      expect(chapterBAfter.downloaded, isTrue);
      expect(chapterBAfter.downloadedPath, '/tmp/b.md');

      // Renames apply in place; new chapters are inserted.
      expect(chapterBAfter.name, 'Chapter 0');
      final chapterD = after.firstWhere((r) => r.url == 'd');
      expect(chapterD.id, isNot(equals(chapterB.id)));
    },
  );

  test('re-syncing the same list is a no-op on row identity', () async {
    final novelId = await seedNovel();
    final list = chaptersFor(novelId, ['a', 'b']);
    await db.chapterDao.syncChaptersForNovel(novelId, list);

    final first = await db.chapterDao.getChaptersForNovel(novelId);
    await db.chapterDao.syncChaptersForNovel(novelId, list);
    final second = await db.chapterDao.getChaptersForNovel(novelId);

    expect(second.map((r) => r.id), first.map((r) => r.id));
  });

  test('sync only touches the given novel', () async {
    final novel1 = await seedNovel();
    final novel2 = await db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            providerId: 'test',
            url: 'https://example.com/novel/2',
            title: 'Other Novel',
            addedAt: 12346,
          ),
        );

    await db.chapterDao.syncChaptersForNovel(
      novel1,
      chaptersFor(novel1, ['a', 'b']),
    );
    await db.chapterDao.syncChaptersForNovel(
      novel2,
      chaptersFor(novel2, ['a', 'b']),
    );

    // Refresh novel 1 down to a single chapter — novel 2 must be untouched.
    await db.chapterDao.syncChaptersForNovel(
      novel1,
      chaptersFor(novel1, ['a']),
    );

    expect(await db.chapterDao.getChapterCount(novel1), 1);
    expect(await db.chapterDao.getChapterCount(novel2), 2);
  });
}
