// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_dao.dart';

// ignore_for_file: type=lint
mixin _$DownloadDaoMixin on DatabaseAccessor<AppDatabase> {
  $NovelsTable get novels => attachedDatabase.novels;
  $ChaptersTable get chapters => attachedDatabase.chapters;
  $DownloadsQueueTable get downloadsQueue => attachedDatabase.downloadsQueue;
  DownloadDaoManager get managers => DownloadDaoManager(this);
}

class DownloadDaoManager {
  final _$DownloadDaoMixin _db;
  DownloadDaoManager(this._db);
  $$NovelsTableTableManager get novels =>
      $$NovelsTableTableManager(_db.attachedDatabase, _db.novels);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db.attachedDatabase, _db.chapters);
  $$DownloadsQueueTableTableManager get downloadsQueue =>
      $$DownloadsQueueTableTableManager(
        _db.attachedDatabase,
        _db.downloadsQueue,
      );
}
