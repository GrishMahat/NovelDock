import 'package:drift/drift.dart';

import '../database.dart';

part 'download_dao.g.dart';

@DriftAccessor(tables: [DownloadsQueue, Novels, Chapters])
class DownloadDao extends DatabaseAccessor<AppDatabase>
    with _$DownloadDaoMixin {
  DownloadDao(super.db);

  Future<int> enqueueDownload(DownloadsQueueCompanion entry) {
    return into(downloadsQueue).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<void> updateDownloadStatus(
    int id,
    String status, {
    double? progress,
    String? error,
  }) async {
    await (update(downloadsQueue)..where((t) => t.id.equals(id))).write(
      DownloadsQueueCompanion(
        status: Value(status),
        progress: Value(progress),
        error: Value(error),
      ),
    );
  }

  Future<void> removeDownload(int id) async {
    await (delete(downloadsQueue)..where((t) => t.id.equals(id))).go();
  }

  Future<DownloadsQueueData?> getDownloadById(int id) {
    return (select(
      downloadsQueue,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<DownloadsQueueData?> getQueuedDownload(int novelId, int chapterId) {
    return (select(downloadsQueue)..where(
          (t) => t.novelId.equals(novelId) & t.chapterId.equals(chapterId),
        ))
        .getSingleOrNull();
  }

  Future<List<DownloadsQueueData>> getAllDownloads() {
    return (select(
      downloadsQueue,
    )..orderBy([(t) => OrderingTerm.desc(t.id)])).get();
  }

  Stream<List<DownloadsQueueData>> watchAllDownloads() {
    return (select(
      downloadsQueue,
    )..orderBy([(t) => OrderingTerm.desc(t.id)])).watch();
  }

  /// Atomically claims the oldest queued task by flipping it to
  /// 'downloading'. Returns null when the queue is empty.
  Future<DownloadsQueueData?> claimNextQueued() async {
    final candidates =
        await (select(downloadsQueue)
              ..where((t) => t.status.equals('queued'))
              ..orderBy([(t) => OrderingTerm.asc(t.id)])
              ..limit(1))
            .get();

    if (candidates.isEmpty) return null;

    final task = candidates.first;

    final updated =
        await (update(downloadsQueue)
              ..where((t) => t.id.equals(task.id) & t.status.equals('queued')))
            .write(const DownloadsQueueCompanion(status: Value('downloading')));

    // Another claim got there first (defensive; we're single-isolate).
    if (updated == 0) return null;

    return await getDownloadById(task.id);
  }

  /// Moves tasks stuck in 'downloading' back to 'queued'. Called on startup:
  /// a 'downloading' row can only be stale if the app died mid-task.
  Future<int> requeueStaleDownloading() {
    return (update(downloadsQueue)
          ..where((t) => t.status.equals('downloading')))
        .write(const DownloadsQueueCompanion(status: Value('queued')));
  }

  Future<List<DownloadsQueueData>> getPendingDownloads() {
    return (select(downloadsQueue)..where(
          (t) => t.status.equals('queued') | t.status.equals('downloading'),
        ))
        .get();
  }

  Stream<List<DownloadsQueueData>> watchPendingDownloads() {
    return (select(downloadsQueue)..where(
          (t) => t.status.equals('queued') | t.status.equals('downloading'),
        ))
        .watch();
  }

  Future<List<DownloadsQueueData>> getCompletedDownloads() {
    return (select(downloadsQueue)
          ..where((t) => t.status.equals('done'))
          ..orderBy([(t) => OrderingTerm.desc(t.id)]))
        .get();
  }

  Future<void> clearCompletedDownloads() async {
    await (delete(downloadsQueue)..where((t) => t.status.equals('done'))).go();
  }
}
