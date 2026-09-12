import 'dart:math';

import 'package:drift/drift.dart';

import '../database.dart';

part 'chapter_dao.g.dart';

@DriftAccessor(
  tables: [
    Chapters,
    Novels,
    ReadingHistory,
    DownloadsQueue,
    Bookmarks,
    Annotations,
    Library,
    NovelProgress,
  ],
)
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

  /// Scoped lookup used by backup restore: chapter URLs are unique per
  /// novel, not globally, so remapping must match within the novel.
  Future<Chapter?> getChapterByNovelAndUrl(int novelId, String url) {
    return (select(chapters)
          ..where((t) => t.novelId.equals(novelId) & t.url.equals(url)))
        .getSingleOrNull();
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

  /// Replaces the stored chapter list for a novel while preserving the
  /// identity (row id) of chapters whose URL still exists.
  ///
  /// The naive approach (delete all + re-insert) churns autoincrement ids,
  /// which orphans everything keyed by chapter id (reading history, download
  /// queue, bookmarks) and destroys per-chapter state (read / ttsRead /
  /// bookmarked / downloaded). Instead this diffs by URL:
  /// - new URLs are inserted,
  /// - existing URLs keep their row (name/index updated in place),
  /// - vanished URLs are deleted **along with their dependent rows**
  ///   (history, queue, bookmarks) and any library/progress anchors pointing
  ///   at them, all inside the same transaction.
  ///
  /// [chapterList] must be the FULL server-side list, not a delta: anything
  /// absent from it is treated as vanished.
  Future<void> syncChaptersForNovel(
    int novelId,
    List<ChaptersCompanion> chapterList,
  ) async {
    await transaction(() async {
      final existing = await (select(
        chapters,
      )..where((t) => t.novelId.equals(novelId))).get();
      final existingByUrl = {for (final c in existing) c.url: c};

      final incomingUrls = <String>{};
      final updates = <Future>[];

      await batch((b) {
        for (final ch in chapterList) {
          final url = ch.url.value;
          incomingUrls.add(url);
          final match = existingByUrl[url];
          if (match == null) {
            b.insert(chapters, ch);
          } else if (match.name != ch.name.value ||
              match.index != ch.index.value) {
            // Rare (renames/reorders) — a targeted in-place update keeps the
            // row id and per-chapter state intact.
            updates.add(
              (update(chapters)..where((t) => t.id.equals(match.id))).write(
                ChaptersCompanion(name: ch.name, index: ch.index),
              ),
            );
          }
        }
      });
      await Future.wait(updates);

      final staleIds = [
        for (final c in existing)
          if (!incomingUrls.contains(c.url)) c.id,
      ];

      // Chunked: SQLite caps bound variables (~999), so very large removals
      // must not go out in a single isIn list.
      const chunkSize = 500;
      for (var i = 0; i < staleIds.length; i += chunkSize) {
        final chunk = staleIds.sublist(i, min(i + chunkSize, staleIds.length));
        // Dependents first (logical order; also future-proof if FK
        // enforcement is ever enabled), chapters last.
        await (delete(
          db.readingHistory,
        )..where((t) => t.chapterId.isIn(chunk))).go();
        await (delete(
          db.downloadsQueue,
        )..where((t) => t.chapterId.isIn(chunk))).go();
        await (delete(
          db.bookmarks,
        )..where((t) => t.chapterId.isIn(chunk))).go();
        await (delete(
          db.annotations,
        )..where((t) => t.chapterId.isIn(chunk))).go();
        await (update(db.library)..where(
              (t) => t.novelId.equals(novelId) & t.lastChapterId.isIn(chunk),
            ))
            .write(const LibraryCompanion(lastChapterId: Value(null)));
        await (update(db.novelProgress)..where(
              (t) =>
                  t.novelId.equals(novelId) & t.lastReadChapterId.isIn(chunk),
            ))
            .write(
              const NovelProgressCompanion(lastReadChapterId: Value(null)),
            );
        await (update(db.novelProgress)..where(
              (t) => t.novelId.equals(novelId) & t.lastTtsChapterId.isIn(chunk),
            ))
            .write(const NovelProgressCompanion(lastTtsChapterId: Value(null)));
        await (delete(
          chapters,
        )..where((t) => t.novelId.equals(novelId) & t.id.isIn(chunk))).go();
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
