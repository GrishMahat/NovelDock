import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'download_dao.g.dart';

@DriftAccessor(tables: [DownloadsQueue, Novels, Chapters])
class DownloadDao extends DatabaseAccessor<AppDatabase>
    with _$DownloadDaoMixin {
  DownloadDao(AppDatabase db) : super(db);

  Future<int> enqueueDownload(DownloadsQueueCompanion entry) {
    return into(downloadsQueue).insert(entry,
        mode: InsertMode.insertOrReplace);
  }

  Future<void> updateDownloadStatus(int id, String status, {double? progress, String? error}) async {
    await (update(downloadsQueue)..where((t) => t.id.equals(id))).write(
        DownloadsQueueCompanion(
      status: Value(status),
      progress: Value(progress),
      error: Value(error),
    ));
  }

  Future<void> removeDownload(int id) async {
    await (delete(downloadsQueue)..where((t) => t.id.equals(id))).go();
  }

  Future<DownloadsQueueData?> getDownloadById(int id) {
    return (select(downloadsQueue)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<DownloadsQueueData?> getQueuedDownload(int novelId, int chapterId) {
    return (select(downloadsQueue)
          ..where((t) =>
              t.novelId.equals(novelId) & t.chapterId.equals(chapterId)))
        .getSingleOrNull();
  }

  Future<List<DownloadsQueueData>> getAllDownloads() {
    return (select(downloadsQueue)
          ..orderBy([(t) => OrderingTerm.desc(t.id)]))
        .get();
  }

  Stream<List<DownloadsQueueData>> watchAllDownloads() {
    return (select(downloadsQueue)
          ..orderBy([(t) => OrderingTerm.desc(t.id)]))
        .watch();
  }

  Future<List<DownloadsQueueData>> getPendingDownloads() {
    return (select(downloadsQueue)
          ..where((t) =>
              t.status.equals('queued') | t.status.equals('downloading')))
        .get();
  }

  Stream<List<DownloadsQueueData>> watchPendingDownloads() {
    return (select(downloadsQueue)
          ..where((t) =>
              t.status.equals('queued') | t.status.equals('downloading')))
        .watch();
  }

  Future<List<DownloadsQueueData>> getCompletedDownloads() {
    return (select(downloadsQueue)
          ..where((t) => t.status.equals('done'))
          ..orderBy([(t) => OrderingTerm.desc(t.id)]))
        .get();
  }

  Future<void> clearCompletedDownloads() async {
    await (delete(downloadsQueue)
          ..where((t) => t.status.equals('done')))
        .go();
  }
}
