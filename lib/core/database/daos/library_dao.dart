import 'package:drift/drift.dart';

import '../database.dart';

part 'library_dao.g.dart';

@DriftAccessor(tables: [Library, Novels, Chapters, ReadingHistory])
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

  Future<void> updateLastRead(int novelId) {
    return (update(library)..where((t) => t.novelId.equals(novelId))).write(
      LibraryCompanion(
        lastReadAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
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

  Future<void> updateOrder(int novelId, int order) {
    return (update(library)..where((t) => t.novelId.equals(novelId))).write(
      LibraryCompanion(order: Value(order)),
    );
  }

  Future<List<LibraryData>> getAllLibraryEntries() {
    return select(library).get();
  }

  Stream<List<LibraryData>> watchAllLibraryEntries() {
    return select(library).watch();
  }

  /// Joined single query (mirrors [watchLibraryNovels]); the old version
  /// issued one query per library entry.
  Future<List<Novel>> getLibraryNovels() {
    final query = select(library).join([
      innerJoin(novels, novels.id.equalsExp(library.novelId)),
    ])..orderBy([OrderingTerm.desc(library.lastReadAt)]);

    return query.map((row) => row.readTable(novels)).get();
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

  Future<List<Novel>> getContinueReadingNovels() async {
    final entries =
        await (select(library)
              ..where((t) => t.lastChapterId.isNotNull())
              ..orderBy([(t) => OrderingTerm.desc(t.lastReadAt)]))
            .get();

    final novels = <Novel>[];
    for (final entry in entries) {
      final lastChapter = await (select(
        db.chapters,
      )..where((t) => t.id.equals(entry.lastChapterId!))).getSingleOrNull();
      // Dangling anchor (chapter vanished before dependent cleanup ran):
      // skip instead of counting the whole novel as unread.
      if (lastChapter == null) continue;

      // COUNT, not full rows: only non-emptiness matters here.
      final unreadCount =
          await (selectOnly(db.chapters)
                ..where(
                  db.chapters.novelId.equals(entry.novelId) &
                      db.chapters.index.isBiggerThanValue(lastChapter.index) &
                      db.chapters.read.equals(false),
                )
                ..addColumns([db.chapters.id.count()]))
              .map((row) => row.read(db.chapters.id.count()) ?? 0)
              .getSingle();

      if (unreadCount > 0) {
        final novel = await (select(
          db.novels,
        )..where((t) => t.id.equals(entry.novelId))).getSingleOrNull();
        if (novel != null) {
          novels.add(novel);
        }
      }
    }
    return novels;
  }
}
