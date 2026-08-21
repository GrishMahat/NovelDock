import 'package:drift/drift.dart';

import '../database.dart';

part 'novel_progress_dao.g.dart';

@DriftAccessor(tables: [NovelProgress, Novels, Chapters])
class NovelProgressDao extends DatabaseAccessor<AppDatabase>
    with _$NovelProgressDaoMixin {
  NovelProgressDao(super.db);

  Future<int> updateProgress({
    required int novelId,
    required int totalChapters,
    int? readChapters,
    int? ttsReadChapters,
    int? lastReadChapterId,
    int? lastTtsChapterId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await (select(
      novelProgress,
    )..where((t) => t.novelId.equals(novelId))).getSingleOrNull();

    if (existing != null) {
      await update(novelProgress).replace(
        NovelProgressCompanion(
          novelId: Value(novelId),
          totalChapters: Value(totalChapters),
          readChapters: Value(readChapters ?? existing.readChapters),
          ttsReadChapters: Value(ttsReadChapters ?? existing.ttsReadChapters),
          lastReadChapterId: lastReadChapterId != null
              ? Value(lastReadChapterId)
              : const Value.absent(),
          lastTtsChapterId: lastTtsChapterId != null
              ? Value(lastTtsChapterId)
              : const Value.absent(),
          lastReadAt: Value(now),
          lastTtsAt: lastTtsChapterId != null
              ? Value(now)
              : const Value.absent(),
        ),
      );
      return 1;
    } else {
      return into(novelProgress).insert(
        NovelProgressCompanion(
          novelId: Value(novelId),
          totalChapters: Value(totalChapters),
          readChapters: Value(readChapters ?? 0),
          ttsReadChapters: Value(ttsReadChapters ?? 0),
          lastReadChapterId: lastReadChapterId != null
              ? Value(lastReadChapterId)
              : const Value.absent(),
          lastTtsChapterId: lastTtsChapterId != null
              ? Value(lastTtsChapterId)
              : const Value.absent(),
          lastReadAt: Value(now),
          lastTtsAt: lastTtsChapterId != null
              ? Value(now)
              : const Value.absent(),
        ),
      );
    }
  }

  Future<NovelProgressData?> getProgress(int novelId) {
    return (select(
      novelProgress,
    )..where((t) => t.novelId.equals(novelId))).getSingleOrNull();
  }

  Stream<NovelProgressData?> watchProgress(int novelId) {
    return (select(
      novelProgress,
    )..where((t) => t.novelId.equals(novelId))).watchSingleOrNull();
  }

  Future<List<NovelProgressData>> getAllProgress() {
    return select(novelProgress).get();
  }

  Future<void> incrementReadChapters(int novelId, int chapterId) async {
    final existing = await getProgress(novelId);
    if (existing == null) return;
    final total = await db.chapterDao.getChapterCount(novelId);
    await updateProgress(
      novelId: novelId,
      totalChapters: total,
      readChapters: existing.readChapters + 1,
      lastReadChapterId: chapterId,
    );
  }

  Future<void> incrementTtsReadChapters(int novelId, int chapterId) async {
    final existing = await getProgress(novelId);
    if (existing == null) return;
    final total = await db.chapterDao.getChapterCount(novelId);
    await updateProgress(
      novelId: novelId,
      totalChapters: total,
      ttsReadChapters: existing.ttsReadChapters + 1,
      lastTtsChapterId: chapterId,
    );
  }

  Future<void> syncProgress(int novelId) async {
    final chapters = await db.chapterDao.getChaptersForNovel(novelId);
    final total = chapters.length;
    final read = chapters.where((c) => c.read).length;
    final ttsRead = chapters.where((c) => c.ttsRead).length;
    final lastRead = chapters.where((c) => c.read).toList()
      ..sort((a, b) => b.index.compareTo(a.index));
    final lastTts = chapters.where((c) => c.ttsRead).toList()
      ..sort((a, b) => b.index.compareTo(a.index));

    await updateProgress(
      novelId: novelId,
      totalChapters: total,
      readChapters: read,
      ttsReadChapters: ttsRead,
      lastReadChapterId: lastRead.isNotEmpty ? lastRead.first.id : null,
      lastTtsChapterId: lastTts.isNotEmpty ? lastTts.first.id : null,
    );
  }
}
