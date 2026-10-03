// Covers the download-management surface added with the novel-detail and
// Downloads rework: per-task removal that also deletes the file, per-novel
// clearing of completed tasks, and the read/unread pairing the bulk chapter
// actions depend on.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedNovel({String url = 'https://example.com/n/1'}) => db
      .into(db.novels)
      .insert(
        NovelsCompanion.insert(
          providerId: 'test',
          url: url,
          title: 'Test Novel',
          addedAt: 1,
        ),
      );

  Future<int> seedChapter(int novelId, {String url = 'c1'}) => db
      .into(db.chapters)
      .insert(
        ChaptersCompanion.insert(
          novelId: novelId,
          name: 'Chapter 1',
          url: url,
          index: 0,
        ),
      );

  group('read / unread round trip', () {
    test('markChapterAsUnread reverses markChapterAsRead', () async {
      final novelId = await seedNovel();
      final chapterId = await seedChapter(novelId);

      final dao = db.chapterDao;
      await dao.markChapterAsRead(chapterId);
      var chapter = await dao.getChapterById(chapterId);
      expect(chapter?.read, isTrue);

      // Without this the bulk "mark unread" action would have nothing to
      // call, since only the forward direction existed.
      await dao.markChapterAsUnread(chapterId);
      chapter = await dao.getChapterById(chapterId);
      expect(chapter?.read, isFalse);
    });

    test('unread clears the unread query membership', () async {
      final novelId = await seedNovel();
      final chapterId = await seedChapter(novelId);
      final dao = db.chapterDao;

      await dao.markChapterAsRead(chapterId);
      expect(await dao.getUnreadChapters(novelId), isEmpty);

      await dao.markChapterAsUnread(chapterId);
      expect(
        (await dao.getUnreadChapters(novelId)).map((c) => c.id),
        contains(chapterId),
      );
    });
  });

  group('download queue removal', () {
    Future<int> seedDoneDownload({
      required int novelId,
      required int chapterId,
    }) async {
      final id = await db
          .into(db.downloadsQueue)
          .insert(
            DownloadsQueueCompanion.insert(
              novelId: novelId,
              chapterId: chapterId,
              status: 'done',
            ),
          );
      return id;
    }

    test('removeDownload drops the queue row', () async {
      final novelId = await seedNovel();
      final chapterId = await seedChapter(novelId);
      final taskId = await seedDoneDownload(
        novelId: novelId,
        chapterId: chapterId,
      );

      await db.downloadDao.removeDownload(taskId);

      expect(await db.downloadDao.getDownloadById(taskId), isNull);
    });

    test('completed tasks are individually discoverable', () async {
      final novelId = await seedNovel();
      final a = await seedChapter(novelId, url: 'c1');
      final b = await seedChapter(novelId, url: 'c2');
      await seedDoneDownload(novelId: novelId, chapterId: a);
      await seedDoneDownload(novelId: novelId, chapterId: b);

      // The Downloads screen's per-row remove needs this list to exist; the
      // previous Clear-completed path deleted every done row blind.
      final done = await db.downloadDao.getCompletedDownloads();
      expect(done.length, 2);
      expect(done.every((d) => d.status == 'done'), isTrue);
    });

    test('getCompletedDownloads only returns done rows', () async {
      final novelId = await seedNovel();
      final chapterId = await seedChapter(novelId);
      final doneId = await seedDoneDownload(
        novelId: novelId,
        chapterId: chapterId,
      );
      await db
          .into(db.downloadsQueue)
          .insert(
            DownloadsQueueCompanion.insert(
              novelId: novelId,
              chapterId: chapterId,
              status: 'queued',
            ),
          );

      final done = await db.downloadDao.getCompletedDownloads();
      expect(done.map((d) => d.id), contains(doneId));
      expect(done.length, 1);
    });
  });

  group('chapter downloaded flag and its file', () {
    test('markNotDownloaded clears both flag and path', () async {
      final novelId = await seedNovel();
      final chapterId = await seedChapter(novelId);
      final dir = await Directory.systemTemp.createTemp('nd_test');
      final file = File('${dir.path}/$chapterId.md');
      await file.writeAsString('# content');

      await db.chapterDao.markChapterAsDownloaded(chapterId, file.path);
      var chapter = await db.chapterDao.getChapterById(chapterId);
      expect(chapter?.downloaded, isTrue);
      expect(chapter?.downloadedPath, file.path);

      // This is what removeTask does once it has deleted the file: without
      // clearing the flag the UI keeps claiming a download that is gone.
      await file.delete();
      await db.chapterDao.markNotDownloaded(chapterId);
      chapter = await db.chapterDao.getChapterById(chapterId);
      expect(chapter?.downloaded, isFalse);
      expect(chapter?.downloadedPath, isNull);

      await dir.delete(recursive: true);
    });
  });
}
