// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'novel_progress_dao.dart';

// ignore_for_file: type=lint
mixin _$NovelProgressDaoMixin on DatabaseAccessor<AppDatabase> {
  $NovelsTable get novels => attachedDatabase.novels;
  $NovelProgressTable get novelProgress => attachedDatabase.novelProgress;
  $ChaptersTable get chapters => attachedDatabase.chapters;
  NovelProgressDaoManager get managers => NovelProgressDaoManager(this);
}

class NovelProgressDaoManager {
  final _$NovelProgressDaoMixin _db;
  NovelProgressDaoManager(this._db);
  $$NovelsTableTableManager get novels =>
      $$NovelsTableTableManager(_db.attachedDatabase, _db.novels);
  $$NovelProgressTableTableManager get novelProgress =>
      $$NovelProgressTableTableManager(_db.attachedDatabase, _db.novelProgress);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db.attachedDatabase, _db.chapters);
}
