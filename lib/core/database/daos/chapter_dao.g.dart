// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chapter_dao.dart';

// ignore_for_file: type=lint
mixin _$ChapterDaoMixin on DatabaseAccessor<AppDatabase> {
  $NovelsTable get novels => attachedDatabase.novels;
  $ChaptersTable get chapters => attachedDatabase.chapters;
  ChapterDaoManager get managers => ChapterDaoManager(this);
}

class ChapterDaoManager {
  final _$ChapterDaoMixin _db;
  ChapterDaoManager(this._db);
  $$NovelsTableTableManager get novels =>
      $$NovelsTableTableManager(_db.attachedDatabase, _db.novels);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db.attachedDatabase, _db.chapters);
}
