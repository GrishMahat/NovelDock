import 'package:drift/drift.dart';

import '../database.dart';

part 'history_dao.g.dart';

@DriftAccessor(tables: [ReadingHistory, Novels, Chapters])
class HistoryDao extends DatabaseAccessor<AppDatabase> with _$HistoryDaoMixin {
  HistoryDao(super.db);

  Future<int> addHistoryEntry(ReadingHistoryCompanion entry) async {
    // Keep only ONE entry per novel in history (standard novel reader behavior)
    final novelId = entry.novelId.value;
    await (delete(
      readingHistory,
    )..where((t) => t.novelId.equals(novelId))).go();
    return into(readingHistory).insert(entry);
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

  Stream<List<ReadingHistoryData>> watchHistoryForNovel(int novelId) {
    return (select(readingHistory)
          ..where((t) => t.novelId.equals(novelId))
          ..orderBy([(t) => OrderingTerm.desc(t.readAt)]))
        .watch();
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

  Future<Map<String, List<ReadingHistoryData>>> getGroupedHistory() async {
    final all = await getAllHistory();
    final grouped = <String, List<ReadingHistoryData>>{};

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    for (final entry in all) {
      final date = DateTime.fromMillisecondsSinceEpoch(entry.readAt);
      final dateOnly = DateTime(date.year, date.month, date.day);

      String group;
      if (dateOnly.isAtSameMomentAs(today)) {
        group = 'Today';
      } else if (dateOnly.isAtSameMomentAs(yesterday)) {
        group = 'Yesterday';
      } else if (dateOnly.isAfter(weekAgo)) {
        group = 'This Week';
      } else {
        group = 'Earlier';
      }

      grouped.putIfAbsent(group, () => []).add(entry);
    }

    return grouped;
  }
}
