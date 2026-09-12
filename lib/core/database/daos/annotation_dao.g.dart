// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'annotation_dao.dart';

// ignore_for_file: type=lint
mixin _$AnnotationDaoMixin on DatabaseAccessor<AppDatabase> {
  $NovelsTable get novels => attachedDatabase.novels;
  $ChaptersTable get chapters => attachedDatabase.chapters;
  $AnnotationsTable get annotations => attachedDatabase.annotations;
  AnnotationDaoManager get managers => AnnotationDaoManager(this);
}

class AnnotationDaoManager {
  final _$AnnotationDaoMixin _db;
  AnnotationDaoManager(this._db);
  $$NovelsTableTableManager get novels =>
      $$NovelsTableTableManager(_db.attachedDatabase, _db.novels);
  $$ChaptersTableTableManager get chapters =>
      $$ChaptersTableTableManager(_db.attachedDatabase, _db.chapters);
  $$AnnotationsTableTableManager get annotations =>
      $$AnnotationsTableTableManager(_db.attachedDatabase, _db.annotations);
}
