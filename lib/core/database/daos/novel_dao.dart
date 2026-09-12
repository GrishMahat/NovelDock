import 'package:drift/drift.dart';

import '../database.dart';

part 'novel_dao.g.dart';

@DriftAccessor(tables: [Novels])
class NovelDao extends DatabaseAccessor<AppDatabase> with _$NovelDaoMixin {
  NovelDao(super.db);

  Future<int> insertNovel(NovelsCompanion novel) {
    return into(novels).insert(novel, mode: InsertMode.insertOrReplace);
  }

  Future<int> updateNovel(NovelsCompanion novel) {
    // Constrain to the companion's primary key: drift's write() alone
    // updates every row, which collides on the id column.
    return (update(
      novels,
    )..where((t) => t.id.equals(novel.id.value))).write(novel);
  }

  Future<int> deleteNovel(int id) {
    return (delete(novels)..where((t) => t.id.equals(id))).go();
  }

  Future<Novel?> getNovelById(int id) {
    return (select(novels)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<Novel?> watchNovelById(int id) {
    return (select(novels)..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<Novel?> getNovelByUrl(String url) {
    return (select(novels)..where((t) => t.url.equals(url))).getSingleOrNull();
  }

  /// Insert-or-get that survives concurrent calls: `insertOrIgnore` absorbs
  /// the UNIQUE(url) race, then the winner's row is read back. Never throws
  /// on duplicates, unlike select-then-insert.
  Future<int> insertOrGetNovel({
    required String providerId,
    required String url,
    required String title,
    String? author,
    String? coverUrl,
  }) async {
    await into(novels).insert(
      NovelsCompanion(
        providerId: Value(providerId),
        url: Value(url),
        title: Value(title),
        author: Value(author),
        coverUrl: Value(coverUrl),
        addedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
      mode: InsertMode.insertOrIgnore,
    );
    final row = await getNovelByUrl(url);
    // The row must exist: either we inserted it or a concurrent call did.
    return row!.id;
  }

  /// Insert the novel if it does not exist yet and report whether the row
  /// was newly created (as opposed to an already-existing one).
  /// `SELECT changes()` is connection-scoped, so inside one transaction it
  /// reports exactly whether our insert wrote (1) or was ignored (0) —
  /// unlike the insert rowid, which is undefined on conflict.
  Future<(int, bool)> insertOrGetNovelWithStatus({
    required String providerId,
    required String url,
    required String title,
    String? author,
    String? coverUrl,
  }) {
    return transaction(() async {
      await into(novels).insert(
        NovelsCompanion(
          providerId: Value(providerId),
          url: Value(url),
          title: Value(title),
          author: Value(author),
          coverUrl: Value(coverUrl),
          addedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
        mode: InsertMode.insertOrIgnore,
      );
      final wrote = await customSelect(
        'SELECT changes() AS c',
      ).map((row) => row.read<int>('c')).getSingle();
      final row = await getNovelByUrl(url);
      return (row!.id, wrote == 1);
    });
  }

  Future<List<Novel>> getAllNovels() {
    return select(novels).get();
  }

  Future<List<Novel>> searchNovels(String query) {
    return (select(novels)..where((t) => t.title.like('%$query%'))).get();
  }

  Future<int> deleteAllNovels() {
    return delete(novels).go();
  }
}
