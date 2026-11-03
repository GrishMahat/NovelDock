import 'package:drift/drift.dart';

import '../database.dart';

part 'library_dao.g.dart';

@DriftAccessor(tables: [Library, Novels])
class LibraryDao extends DatabaseAccessor<AppDatabase> with _$LibraryDaoMixin {
  LibraryDao(super.db);

  Future<int> addToLibrary(int novelId, {String? status}) async {
    // Transacted: concurrent adds must not interleave into duplicate rows.
    return transaction(() async {
      final existing = await isInLibrary(novelId);
      if (existing) {
        await (update(library)..where((t) => t.novelId.equals(novelId))).write(
          LibraryCompanion(
            lastReadAt: Value(DateTime.now().millisecondsSinceEpoch),
            status: Value(status ?? 'Reading'),
          ),
        );
        return novelId;
      }
      return into(library).insert(
        LibraryCompanion(
          novelId: Value(novelId),
          lastReadAt: Value(DateTime.now().millisecondsSinceEpoch),
          status: Value(status ?? 'Reading'),
        ),
      );
    });
  }

  Future<void> updateStatus(int novelId, String? status) {
    return (update(library)..where((t) => t.novelId.equals(novelId))).write(
      LibraryCompanion(status: Value(status)),
    );
  }

  Future<bool> removeFromLibrary(int novelId) async {
    final count = await (delete(
      library,
    )..where((t) => t.novelId.equals(novelId))).go();
    return count > 0;
  }

  Future<bool> isInLibrary(int novelId) async {
    final result = await (select(
      library,
    )..where((t) => t.novelId.equals(novelId))).getSingleOrNull();
    return result != null;
  }

  Future<LibraryData?> getLibraryEntry(int novelId) {
    return (select(
      library,
    )..where((t) => t.novelId.equals(novelId))).getSingleOrNull();
  }

  Future<List<LibraryData>> getAllLibraryEntries() {
    return select(library).get();
  }

  Stream<List<LibraryData>> watchAllLibraryEntries() {
    return select(library).watch();
  }

  Stream<List<Novel>> watchLibraryNovels() {
    final query = select(library).join([
      innerJoin(novels, novels.id.equalsExp(library.novelId)),
    ])..orderBy([OrderingTerm.desc(library.lastReadAt)]);

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(novels)).toList(),
    );
  }

  Stream<List<Novel>> watchLibraryNovelsByStatus(String status) {
    final query =
        select(
            library,
          ).join([innerJoin(novels, novels.id.equalsExp(library.novelId))])
          ..where(library.status.equals(status))
          ..orderBy([OrderingTerm.desc(library.lastReadAt)]);

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(novels)).toList(),
    );
  }
}
