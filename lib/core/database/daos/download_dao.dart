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

  /// Bulk enqueue in one batch. Callers dedupe first and kick the queue once
  /// after (see DownloadNotifier._enqueueChapters): per-row progress updates
  /// and pool kicks per chapter do not scale to 1000-chapter novels.
  Future<void> enqueueAll(List<DownloadsQueueCompanion> entries) async {
    if (entries.isEmpty) return;
    await batch((b) {
      for (final entry in entries) {
        b.insert(downloadsQueue, entry, mode: InsertMode.insertOrReplace);
      }
    });
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

  /// Novel-scoped rows. Prefer this over getAllDownloads + Dart filtering:
  /// the queue table grows with every novel ever downloaded.
  Future<List<DownloadsQueueData>> getDownloadsForNovel(int novelId) {
    return (select(
      downloadsQueue,
    )..where((t) => t.novelId.equals(novelId))).get();
  }

  /// Per-status counts for one novel in a single GROUP BY query. The queue
  /// tile and notifications refresh on every task transition; full-table
  /// scans there do not scale.
  Future<Map<String, int>> countByStatus(int novelId) async {
    final count = downloadsQueue.id.count();
    final rows =
        await (selectOnly(downloadsQueue)
              ..where(downloadsQueue.novelId.equals(novelId))
              ..addColumns([downloadsQueue.status, count])
              ..groupBy([downloadsQueue.status]))
            .map(
              (row) => MapEntry(
                row.read(downloadsQueue.status) ?? '',
                row.read(count) ?? 0,
              ),
            )
            .get();
    return Map.fromEntries(rows);
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
