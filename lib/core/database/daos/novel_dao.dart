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
    return (update(novels)..where((t) => t.id.equals(novel.id.value)))
        .write(novel);
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

  Future<int> insertOrGetNovel({
    required String providerId,
    required String url,
    required String title,
    String? author,
    String? coverUrl,
  }) async {
    final existing = await getNovelByUrl(url);
    if (existing != null) return existing.id;
    return insertNovel(NovelsCompanion(
      providerId: Value(providerId),
      url: Value(url),
      title: Value(title),
      author: Value(author),
      coverUrl: Value(coverUrl),
      addedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
  }

  /// Insert the novel if it does not exist yet and report whether the row
  /// was newly created (as opposed to an already-existing one).
  Future<(int, bool)> insertOrGetNovelWithStatus({
    required String providerId,
    required String url,
    required String title,
    String? author,
    String? coverUrl,
  }) async {
    final existing = await getNovelByUrl(url);
    if (existing != null) return (existing.id, false);
    final id = await insertNovel(NovelsCompanion(
      providerId: Value(providerId),
      url: Value(url),
      title: Value(title),
      author: Value(author),
      coverUrl: Value(coverUrl),
      addedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
    return (id, true);
  }

  Future<List<Novel>> getAllNovels() {
    return select(novels).get();
  }

  Future<List<Novel>> searchNovels(String query) {
    return (select(novels)
          ..where((t) => t.title.like('%$query%')))
        .get();
  }

  Future<int> deleteAllNovels() {
    return delete(novels).go();
  }
}
