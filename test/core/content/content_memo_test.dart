// Pins ContentNotifier's chapter memo: a chapter is read from its source once
// per session, and only a cached success short-circuits a repeat load.
//
// `loadChapter` is called from the reader's current-chapter change, from
// `preloadSurrounding`, and from the ahead-of-scroll prefetch, so several call
// sites ask for the same chapter in one session. If the short-circuit at the
// top of `loadChapter` regresses, each becomes another disk read or network
// fetch — invisible in normal use, and slow while scrolling fast.
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/content/providers/content_provider.dart';
import 'package:noveldock/core/database/database.dart';
import 'package:noveldock/core/network/client.dart';
import 'package:noveldock/core/providers/database_providers.dart';
import 'package:noveldock/core/providers/engine.dart';

/// Reports every `getChapterById` so a test can tell a real load attempt
/// apart from a cache short-circuit.
class _CountingChapterDao extends ChapterDao {
  final void Function() onRead;

  _CountingChapterDao(super.db, {required this.onRead});

  @override
  Future<Chapter?> getChapterById(int id) {
    onRead();
    return super.getChapterById(id);
  }
}

void main() {
  late AppDatabase db;
  late Directory tempDir;
  late ProviderContainer container;
  late int chapterId;

  /// Lets a test tell a real load attempt apart from a cache short-circuit.
  /// The provider-instance family is keepAlive and would only count once.
  int chapterReads = 0;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('content_memo_test');
    chapterReads = 0;

    final novelId = await db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            providerId: 'test',
            url: 'https://example.com/novel/1',
            title: 'Test Novel',
            addedAt: 12345,
          ),
        );

    // A real file on disk, so the loader succeeds without any network.
    final file = File('${tempDir.path}/ch1.md');
    await file.writeAsString('# Chapter One\n\nBody text.\n');

    chapterId = await db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            novelId: novelId,
            name: 'Chapter 1',
            url: 'https://example.com/novel/1/ch1',
            index: 0,
          ).copyWith(
            downloaded: const Value(true),
            downloadedPath: Value(file.path),
          ),
        );

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // Keeps imageHeadersForUrl off the real AppConfig/path_provider path.
        cookieJarProvider.overrideWith((ref) async => CookieJar()),
        // Makes RemoteLoader throw without touching the JS registry or a socket.
        providerInstanceProvider.overrideWith((ref, providerId) async => null),
        chapterDaoProvider.overrideWith((ref) {
          final dao = _CountingChapterDao(db, onRead: () => chapterReads++);
          ref.onDispose(dao.close);
          return dao;
        }),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Future<String?> loadOnce() async {
    final notifier = container.read(contentProvider.notifier);
    await notifier.loadChapter(chapterId);
    return notifier.getContentMd(chapterId);
  }

  test('first load reads the chapter and exposes it as markdown', () async {
    expect(await loadOnce(), contains('Body text.'));
  });

  test('repeat load of a cached chapter does not re-read the source', () async {
    expect(await loadOnce(), contains('Body text.'));

    // Delete the backing file: a re-read would throw, so surviving proves the
    // cached success short-circuited the second load.
    final file = File('${tempDir.path}/ch1.md');
    await file.delete();

    final notifier = container.read(contentProvider.notifier);
    await notifier.loadChapter(chapterId);

    expect(
      notifier.getContentMd(chapterId),
      contains('Body text.'),
      reason: 'a cached chapter must not hit the source again',
    );
    expect(
      container.read(contentProvider).chapters[chapterId],
      isA<AsyncData<Object?>>(),
      reason: 'the repeat load must not overwrite success with an error',
    );
    expect(
      chapterReads,
      1,
      reason: 'the second load must short-circuit before any loader work',
    );
  });

  test('clearCache drops the memo so the next load reads again', () async {
    expect(await loadOnce(), contains('Body text.'));

    final notifier = container.read(contentProvider.notifier);
    notifier.clearCache();
    expect(notifier.getContentMd(chapterId), isNull);
    expect(container.read(contentProvider).chapters, isEmpty);

    // Source still there: the chapter reloads cleanly, so clearCache discarded
    // the memo rather than poisoning the entry.
    expect(await loadOnce(), contains('Body text.'));
  });

  test('a stored error does not block a retry', () async {
    final file = File('${tempDir.path}/ch1.md');
    await file.delete();

    // The notifier heals the flag and refetches remotely, which fails here.
    await loadOnce();
    final notifier = container.read(contentProvider.notifier);
    expect(
      container.read(contentProvider).chapters[chapterId],
      isA<AsyncError<Object?>>(),
    );
    expect(chapterReads, 1);

    // The reader's Retry button calls loadChapter for the same id, so a
    // stored error must not be treated as a cache hit.
    await notifier.loadChapter(chapterId);
    expect(
      chapterReads,
      2,
      reason: 'a retry must re-enter the loader rather than short-circuit',
    );
  });
}
