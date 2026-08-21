import 'package:drift/drift.dart';

import '../database.dart';

part 'chapter_dao.g.dart';

@DriftAccessor(tables: [Chapters, Novels])
class ChapterDao extends DatabaseAccessor<AppDatabase> with _$ChapterDaoMixin {
  ChapterDao(super.db);

  Future<int> insertChapter(ChaptersCompanion chapter) {
    return into(chapters).insert(chapter, mode: InsertMode.insertOrReplace);
  }

  /// Partially updates a chapter (only columns present in [chapter] are set).
  Future<int> updateChapter(ChaptersCompanion chapter) {
    return (update(
      chapters,
    )..where((t) => t.id.equals(chapter.id.value))).write(chapter);
  }

  Future<int> deleteChapter(int id) {
    return (delete(chapters)..where((t) => t.id.equals(id))).go();
  }

  Future<int> deleteChaptersForNovel(int novelId) {
    return (delete(chapters)..where((t) => t.novelId.equals(novelId))).go();
  }

  Future<Chapter?> getChapterById(int id) {
    return (select(chapters)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<Chapter?> getChapterByUrl(String url) {
    return (select(
      chapters,
    )..where((t) => t.url.equals(url))).getSingleOrNull();
  }

  Future<List<Chapter>> getChaptersForNovel(int novelId) {
    return (select(chapters)
          ..where((t) => t.novelId.equals(novelId))
          ..orderBy([(t) => OrderingTerm.asc(t.index)]))
        .get();
  }

  Future<List<Chapter>> getDownloadedChapters(int novelId) {
    return (select(chapters)
          ..where((t) => t.novelId.equals(novelId) & t.downloaded.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.index)]))
        .get();
  }

  Future<List<Chapter>> getUnreadChapters(int novelId) {
    return (select(chapters)
          ..where((t) => t.novelId.equals(novelId) & t.read.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.index)]))
        .get();
  }

  Future<void> markChapterAsRead(int chapterId) {
    return (update(chapters)..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(read: const Value(true)),
    );
  }

  Future<void> markChapterAsTtsRead(int chapterId) {
    return (update(chapters)..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(ttsRead: const Value(true)),
    );
  }

  Future<void> markChapterAsDownloaded(int chapterId, String path) {
    return (update(chapters)..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(
        downloaded: const Value(true),
        downloadedPath: Value(path),
      ),
    );
  }

  Future<void> markNotDownloaded(int chapterId) {
    return (update(chapters)..where((t) => t.id.equals(chapterId))).write(
      const ChaptersCompanion(
        downloaded: Value(false),
        downloadedPath: Value(null),
      ),
    );
  }

  Future<void> toggleBookmark(int chapterId, bool bookmarked) {
    return (update(chapters)..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(bookmarked: Value(bookmarked)),
    );
  }

  Future<void> insertChaptersForNovel(
    int novelId,
    List<ChaptersCompanion> chapterList,
  ) async {
    await transaction(() async {
      await (delete(chapters)..where((t) => t.novelId.equals(novelId))).go();
      for (final ch in chapterList) {
        await into(chapters).insert(ch, mode: InsertMode.insertOrReplace);
      }
    });
  }

  Future<int> getChapterCount(int novelId) {
    return (selectOnly(chapters)
          ..where(chapters.novelId.equals(novelId))
          ..addColumns([chapters.id.count()]))
        .map((row) => row.read(chapters.id.count()) ?? 0)
        .getSingle();
  }

  Stream<List<Chapter>> watchChaptersForNovel(int novelId) {
    return (select(chapters)
          ..where((t) => t.novelId.equals(novelId))
          ..orderBy([(t) => OrderingTerm.asc(t.index)]))
        .watch();
  }
}
