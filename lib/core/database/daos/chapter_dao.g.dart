// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapter_dao.dart';

// ignore_for_file: type=lint
mixin _$ChapterDaoMixin on DatabaseAccessor<AppDatabase> {
  $NovelsTable get novels => attachedDatabase.novels;
  $ChaptersTable get chapters => attachedDatabase.chapters;
  $ReadingHistoryTable get readingHistory => attachedDatabase.readingHistory;
  $DownloadsQueueTable get downloadsQueue => attachedDatabase.downloadsQueue;
  $BookmarksTable get bookmarks => attachedDatabase.bookmarks;
  $AnnotationsTable get annotations => attachedDatabase.annotations;
  $LibraryTable get library => attachedDatabase.library;
  $NovelProgressTable get novelProgress => attachedDatabase.novelProgress;
  ChapterDaoManager get managers => ChapterDaoManager(this);
}

class ChapterDaoManager {
  final _$ChapterDaoMixin _db;
  ChapterDaoManager(this._db);
  $$NovelsTableTableManager get novels =>
      $$NovelsTableTableManager(_db.attachedDatabase, _db.novels);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db.attachedDatabase, _db.chapters);
  $$ReadingHistoryTableTableManager get readingHistory =>
      $$ReadingHistoryTableTableManager(
        _db.attachedDatabase,
        _db.readingHistory,
      );
  $$DownloadsQueueTableTableManager get downloadsQueue =>
      $$DownloadsQueueTableTableManager(
        _db.attachedDatabase,
        _db.downloadsQueue,
      );
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db.attachedDatabase, _db.bookmarks);
  $$AnnotationsTableTableManager get annotations =>
      $$AnnotationsTableTableManager(_db.attachedDatabase, _db.annotations);
  $$LibraryTableTableManager get library =>
      $$LibraryTableTableManager(_db.attachedDatabase, _db.library);
  $$NovelProgressTableTableManager get novelProgress =>
      $$NovelProgressTableTableManager(_db.attachedDatabase, _db.novelProgress);
}
