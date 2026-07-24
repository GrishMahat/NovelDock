import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'bookmark_dao.g.dart';

@DriftAccessor(tables: [Bookmarks, Novels, Chapters])
class BookmarkDao extends DatabaseAccessor<AppDatabase>
    with _$BookmarkDaoMixin {
  BookmarkDao(AppDatabase db) : super(db);

  Future<int> addBookmark(BookmarksCompanion bookmark) {
    return into(bookmarks).insert(bookmark,
        mode: InsertMode.insertOrReplace);
  }

  Future<void> removeBookmark(int id) async {
    await (delete(bookmarks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> removeBookmarkForPosition(int novelId, int chapterId, String position) async {
    await (delete(bookmarks)
          ..where((t) =>
              t.novelId.equals(novelId) &
              t.chapterId.equals(chapterId) &
              t.position.equals(position)))
        .go();
  }

  Future<List<Bookmark>> getBookmarksForNovel(int novelId) {
    return (select(bookmarks)
          ..where((t) => t.novelId.equals(novelId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Stream<List<Bookmark>> watchBookmarksForNovel(int novelId) {
    return (select(bookmarks)
          ..where((t) => t.novelId.equals(novelId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<List<Bookmark>> getAllBookmarks() {
    return (select(bookmarks)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<bool> hasBookmark(int novelId, int chapterId, String position) async {
    final result = await (select(bookmarks)
          ..where((t) =>
              t.novelId.equals(novelId) &
              t.chapterId.equals(chapterId) &
              t.position.equals(position)))
        .getSingleOrNull();
    return result != null;
  }
}
