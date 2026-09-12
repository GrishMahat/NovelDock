import 'package:drift/drift.dart';

import '../database.dart';

part 'annotation_dao.g.dart';

@DriftAccessor(tables: [Annotations, Novels, Chapters])
class AnnotationDao extends DatabaseAccessor<AppDatabase>
    with _$AnnotationDaoMixin {
  AnnotationDao(super.db);

  Future<int> addAnnotation(AnnotationsCompanion entry) {
    return into(annotations).insert(entry);
  }

  Future<void> removeAnnotation(int id) async {
    await (delete(annotations)..where((t) => t.id.equals(id))).go();
  }

  Future<void> updateNote(int id, String? note) {
    return (update(annotations)..where((t) => t.id.equals(id))).write(
      AnnotationsCompanion(note: Value(note)),
    );
  }

  Future<Annotation?> getForPosition(
    int novelId,
    int chapterId,
    int paragraphIndex,
  ) {
    return (select(annotations)..where(
          (t) =>
              t.novelId.equals(novelId) &
              t.chapterId.equals(chapterId) &
              t.paragraphIndex.equals(paragraphIndex),
        ))
        .getSingleOrNull();
  }

  Future<List<Annotation>> getForNovel(int novelId) {
    return (select(annotations)
          ..where((t) => t.novelId.equals(novelId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.chapterId),
            (t) => OrderingTerm.asc(t.paragraphIndex),
          ]))
        .get();
  }

  Stream<List<Annotation>> watchForNovel(int novelId) {
    return (select(annotations)
          ..where((t) => t.novelId.equals(novelId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.chapterId),
            (t) => OrderingTerm.asc(t.paragraphIndex),
          ]))
        .watch();
  }
}
