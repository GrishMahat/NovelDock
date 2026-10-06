import 'package:drift/drift.dart';

import '../database.dart';

part 'history_dao.g.dart';

@DriftAccessor(tables: [ReadingHistory, Novels, Chapters])
class HistoryDao extends DatabaseAccessor<AppDatabase> with _$HistoryDaoMixin {
  HistoryDao(super.db);

  Future<int> addHistoryEntry(ReadingHistoryCompanion entry) async {
    // Keep only ONE row per novel. Update instead of delete+insert so
    // columns absent from [entry] (e.g. scrollPosition on a plain chapter
    // open) keep their previous values instead of wiping the resume anchor.
    // Transacted: concurrent opens must not interleave into duplicate rows.
    return transaction(() async {
      final novelId = entry.novelId.value;
      final existing =
          await (select(readingHistory)
                ..where((t) => t.novelId.equals(novelId))
                ..orderBy([(t) => OrderingTerm.desc(t.readAt)])
                ..limit(1))
              .get();

      if (existing.isNotEmpty) {
        await (update(
          readingHistory,
        )..where((t) => t.id.equals(existing.first.id))).write(entry);

        return existing.first.id;
      }

      return into(readingHistory).insert(entry);
    });
  }

  Future<void> deleteHistoryEntry(int id) {
    return (delete(readingHistory)..where((t) => t.id.equals(id))).go();
  }

  Future<void> clearHistory() {
    return delete(readingHistory).go();
  }

  Future<void> clearHistoryForNovel(int novelId) {
    return (delete(
      readingHistory,
    )..where((t) => t.novelId.equals(novelId))).go();
  }

  Future<List<ReadingHistoryData>> getHistoryForNovel(int novelId) {
    return (select(readingHistory)
          ..where((t) => t.novelId.equals(novelId))
          ..orderBy([(t) => OrderingTerm.desc(t.readAt)]))
        .get();
  }

  Future<ReadingHistoryData?> getLatestHistoryForNovel(int novelId) {
    return (select(readingHistory)
          ..where((t) => t.novelId.equals(novelId))
          ..orderBy([(t) => OrderingTerm.desc(t.readAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<List<ReadingHistoryData>> getAllHistory() {
    return (select(
      readingHistory,
    )..orderBy([(t) => OrderingTerm.desc(t.readAt)])).get();
  }

  Stream<List<ReadingHistoryData>> watchAllHistory() {
    return (select(
      readingHistory,
    )..orderBy([(t) => OrderingTerm.desc(t.readAt)])).watch();
  }
}
