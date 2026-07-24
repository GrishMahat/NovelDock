// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'novel_dao.dart';

// ignore_for_file: type=lint
mixin _$NovelDaoMixin on DatabaseAccessor<AppDatabase> {
  $NovelsTable get novels => attachedDatabase.novels;
  NovelDaoManager get managers => NovelDaoManager(this);
}

class NovelDaoManager {
  final _$NovelDaoMixin _db;
  NovelDaoManager(this._db);
  $$NovelsTableTableManager get novels =>
      $$NovelsTableTableManager(_db.attachedDatabase, _db.novels);
}
