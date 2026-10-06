import 'package:drift/drift.dart';

import '../database.dart';

part 'bookmark_dao.g.dart';

@DriftAccessor(tables: [Bookmarks, Novels, Chapters])
class BookmarkDao extends DatabaseAccessor<AppDatabase>
    with _$BookmarkDaoMixin {
  BookmarkDao(super.db);

  /// Idempotent insert: an identical (novel, chapter, position) row is
  /// returned as-is instead of duplicated. Guards reader double-taps and
  /// backup re-imports (which carry no source-DB ids to conflict on — the
  /// table has no unique constraint, so insertOrReplace never replaced).
  Future<int> addBookmark(BookmarksCompanion bookmark) async {
    // position is nullable: only absent-position rows skip the check.
    final position = bookmark.position.value;
    if (position != null) {
      final existing =
          await (select(bookmarks)..where(
                (t) =>
                    t.novelId.equals(bookmark.novelId.value) &
                    t.chapterId.equals(bookmark.chapterId.value) &
                    t.position.equals(position),
              ))
              .getSingleOrNull();
      if (existing != null) return existing.id;
    }
    return into(bookmarks).insert(bookmark);
  }

  Future<void> removeBookmark(int id) async {
    await (delete(bookmarks)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Bookmark>> getBookmarksForNovel(int novelId) {
    return (select(bookmarks)
          ..where((t) => t.novelId.equals(novelId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<List<Bookmark>> getBookmarksForChapter(int chapterId) {
    return (select(
      bookmarks,
    )..where((t) => t.chapterId.equals(chapterId))).get();
  }

  Future<List<Bookmark>> getAllBookmarks() {
    return (select(
      bookmarks,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
  }
}
