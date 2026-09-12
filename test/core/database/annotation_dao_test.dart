import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/database/database.dart';

// Reader highlights: position-keyed round trip, per-novel streaming order,
// note updates, and removal.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<int> seedNovel() {
    return db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            providerId: 'test',
            url: 'https://example.com/novel/1',
            title: 'Test Novel',
            addedAt: 1,
          ),
        );
  }

  Future<int> seedChapter(int novelId, String url) {
    return db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            novelId: novelId,
            name: 'Chapter $url',
            url: url,
            index: 0,
          ),
        );
  }

  Future<int> highlight(
    int novelId,
    int chapterId, {
    int paragraph = 0,
    String? note,
  }) {
    return db.annotationDao.addAnnotation(
      AnnotationsCompanion.insert(
        novelId: novelId,
        chapterId: chapterId,
        chapterUrl: 'url-$chapterId',
        paragraphIndex: paragraph,
        quote: 'quoted text $paragraph',
        note: note == null ? const Value.absent() : Value(note),
        createdAt: 1,
      ),
    );
  }

  test('round trip by position', () async {
    final novelId = await seedNovel();
    final chapterId = await seedChapter(novelId, 'a');
    await highlight(novelId, chapterId, paragraph: 3, note: 'why');

    final found = await db.annotationDao.getForPosition(novelId, chapterId, 3);
    expect(found, isNotNull);
    expect(found!.quote, 'quoted text 3');
    expect(found.note, 'why');

    expect(
      await db.annotationDao.getForPosition(novelId, chapterId, 4),
      isNull,
    );
  });

  test('novel list ordered by chapter then paragraph', () async {
    final novelId = await seedNovel();
    final c1 = await seedChapter(novelId, 'a');
    final c2 = await seedChapter(novelId, 'b');
    await highlight(novelId, c2, paragraph: 0);
    await highlight(novelId, c1, paragraph: 2);
    await highlight(novelId, c1, paragraph: 0);

    final rows = await db.annotationDao.getForNovel(novelId);
    expect(rows.map((r) => (r.chapterId, r.paragraphIndex)), [
      (c1, 0),
      (c1, 2),
      (c2, 0),
    ]);
  });

  test('note update and removal', () async {
    final novelId = await seedNovel();
    final chapterId = await seedChapter(novelId, 'a');
    final id = await highlight(novelId, chapterId);

    await db.annotationDao.updateNote(id, 'edited');
    expect(
      (await db.annotationDao.getForPosition(novelId, chapterId, 0))!.note,
      'edited',
    );

    await db.annotationDao.removeAnnotation(id);
    expect(
      await db.annotationDao.getForPosition(novelId, chapterId, 0),
      isNull,
    );
  });

  test('stream emits on insert', () async {
    final novelId = await seedNovel();
    final chapterId = await seedChapter(novelId, 'a');

    final future = db.annotationDao.watchForNovel(novelId).first;
    await highlight(novelId, chapterId);
    expect(await future, hasLength(1));
  });
}
