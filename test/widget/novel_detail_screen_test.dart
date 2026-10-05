import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noveldock/core/config/app_prefs.dart';
import 'package:noveldock/core/database/database.dart';
import 'package:noveldock/core/providers/database_providers.dart';
import 'package:noveldock/core/providers/novel_fetch_state.dart';
import 'package:noveldock/features/novel/novel_detail_screen.dart';
import 'package:noveldock/widgets/shimmer_list.dart';

/// Deterministically failed fetch for failure-UI tests (no network).
class _FailedFetchNotifier extends NovelFetchStateNotifier {
  @override
  NovelFetchState build(int novelId) =>
      const NovelFetchState(phase: NovelFetchPhase.failed);
}

Widget _stub(String label) => Scaffold(body: Center(child: Text(label)));

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase db,
  SharedPreferences prefs,
) async {
  final router = GoRouter(
    initialLocation: '/novel/1',
    routes: [
      GoRoute(
        path: '/novel/:id',
        builder: (_, state) => NovelDetailScreen(
          novelId: int.parse(state.pathParameters['id'] ?? '0'),
        ),
      ),
      GoRoute(
        path: '/reader/:novelId/:chapterId',
        builder: (_, _) => _stub('reader'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        appPrefsProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // No pumpAndSettle: shimmer placeholders animate forever while visible.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// See library_screen_test.dart: unmount + flush drift close timers in-test.
Future<void> _settleAndClose(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(Container());
  await tester.pump(const Duration(milliseconds: 200));
  await db.close();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    final novelId = await db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            providerId: 'test',
            url: 'https://example.com/novel/1',
            title: 'Filter Novel',
            addedAt: 1,
          ),
        );
    Future<void> chapter(
      String name,
      double index, {
      bool downloaded = false,
      String? downloadedPath,
      bool read = false,
      bool bookmarked = false,
    }) => db
        .into(db.chapters)
        .insert(
          ChaptersCompanion.insert(
            novelId: novelId,
            name: name,
            url: 'c$index',
            index: index,
            downloaded: Value(downloaded),
            downloadedPath: Value(downloadedPath),
            read: Value(read),
            bookmarked: Value(bookmarked),
          ),
        );
    // A real on-disk file: the detail screen reconciles downloads on open,
    // and a downloaded flag without a file is (correctly) cleared.
    final downloadedFile = File(
      '${Directory.systemTemp.path}/filter_novel_ch1.md',
    );
    await downloadedFile.writeAsString('# Downloaded Chapter\n\ntext');
    addTearDown(() async {
      if (await downloadedFile.exists()) await downloadedFile.delete();
    });
    await chapter('Plain Chapter', 0);
    await chapter(
      'Downloaded Chapter',
      1,
      downloaded: true,
      downloadedPath: downloadedFile.path,
    );
    await chapter('Read Chapter', 2, read: true);
    await chapter('Bookmarked Chapter', 3, bookmarked: true);
  });

  // DB is closed per-test via _settleAndClose (see above); nothing here.

  Future<void> openFilter(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('chapter-filter')));
    await tester.pumpAndSettle();
  }

  testWidgets('the filter is one button that opens a checkbox popup', (
    tester,
  ) async {
    await _pumpDetail(tester, db, prefs);
    expect(find.text('4 chapters'), findsOneWidget);
    expect(find.byKey(const ValueKey('chapter-filter')), findsOneWidget);
    // No chip row: the four states live behind the button.
    expect(find.text('Downloaded'), findsNothing);

    await openFilter(tester);
    for (final label in ['Downloaded', 'Bookmarked', 'Read', 'Unread']) {
      expect(find.text(label), findsOneWidget, reason: '$label missing');
    }
    expect(find.text('Done'), findsOneWidget);
    // Nothing ticked, so the list is untouched behind the popup.
    expect(find.text('4 chapters'), findsOneWidget);
    await _settleAndClose(tester, db);
  });

  testWidgets('Downloaded filter narrows the list', (tester) async {
    await _pumpDetail(tester, db, prefs);
    await openFilter(tester);
    await tester.tap(find.text('Downloaded'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('1 of 4 chapters'), findsOneWidget);
    expect(find.text('Downloaded Chapter'), findsOneWidget);
    expect(find.text('Plain Chapter'), findsNothing);
    await _settleAndClose(tester, db);
  });

  testWidgets('Unread filter excludes read chapters', (tester) async {
    await _pumpDetail(tester, db, prefs);
    await openFilter(tester);
    await tester.tap(find.text('Unread'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('3 of 4 chapters'), findsOneWidget);
    expect(find.text('Read Chapter'), findsNothing);
    expect(find.text('Plain Chapter'), findsOneWidget);
    await _settleAndClose(tester, db);
  });

  testWidgets('Bookmarked filter shows only bookmarked', (tester) async {
    await _pumpDetail(tester, db, prefs);
    await openFilter(tester);
    await tester.tap(find.text('Bookmarked'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('1 of 4 chapters'), findsOneWidget);
    expect(find.text('Bookmarked Chapter'), findsOneWidget);
    await _settleAndClose(tester, db);
  });

  testWidgets('filters are multi-select and combine as a union', (
    tester,
  ) async {
    await _pumpDetail(tester, db, prefs);
    await openFilter(tester);

    await tester.tap(find.text('Downloaded'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookmarked'));
    await tester.pumpAndSettle();

    // The popup must not close on a tick — that is the whole point of the
    // checkboxes instead of menu items.
    CheckboxListTile box(String label) => tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, label),
    );
    expect(box('Downloaded').value, isTrue);
    expect(box('Bookmarked').value, isTrue);
    expect(box('Read').value, isFalse);

    // Downloaded (1) ∪ Bookmarked (1) = 2 of 4.
    expect(find.text('2 of 4 chapters'), findsOneWidget);
    expect(find.byTooltip('Filter chapters (2)'), findsOneWidget);
    expect(find.text('Downloaded Chapter'), findsOneWidget);
    expect(find.text('Bookmarked Chapter'), findsOneWidget);
    expect(find.text('Plain Chapter'), findsNothing);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Downloaded'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('4 chapters'), findsOneWidget);
    expect(find.text('Plain Chapter'), findsOneWidget);
    expect(find.byTooltip('Filter chapters'), findsOneWidget);
    await _settleAndClose(tester, db);
  });

  testWidgets('the chapter header fits a 360dp phone with a filter active', (
    tester,
  ) async {
    // 360dp is the common low end (see mobile_density_test). Two rows are
    // squeezed here: the chapter header (count, an active Filter label, Clear
    // and Sort on one line) and the library/source actions beside the cover,
    // which used to overflow this width by 9.5px once the status label ran
    // long. Wrap catches it; nothing may paint a red overflow bar.
    tester.view.physicalSize = const Size(360, 800) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _pumpDetail(tester, db, prefs);
    await tester.ensureVisible(find.byKey(const ValueKey('chapter-filter')));
    await tester.pumpAndSettle();

    await openFilter(tester);
    await tester.tap(find.text('Downloaded'));
    await tester.tap(find.text('Bookmarked'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2 of 4 chapters'), findsOneWidget);
    expect(find.byTooltip('Filter chapters (2)'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.byKey(const ValueKey('novel-overflow')), findsOneWidget);

    await _settleAndClose(tester, db);
  });

  Future<int> seedEmptyNovel({String providerId = 'test'}) {
    return db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            providerId: providerId,
            url: 'https://example.com/empty',
            title: 'Empty Novel',
            addedAt: 1,
          ),
        );
  }

  Future<void> pumpNovel(WidgetTester tester, int novelId) async {
    final router = GoRouter(
      initialLocation: '/novel/$novelId',
      routes: [
        GoRoute(
          path: '/novel/:id',
          builder: (_, state) => NovelDetailScreen(
            novelId: int.parse(state.pathParameters['id'] ?? '0'),
          ),
        ),
        GoRoute(
          path: '/reader/:novelId/:chapterId',
          builder: (_, _) => _stub('reader'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appPrefsProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
  }

  testWidgets('empty remote novel shows loading, not "no chapters"', (
    tester,
  ) async {
    final id = await seedEmptyNovel();
    await pumpNovel(tester, id);
    // The open-time auto-fetch is still running here, so the skeleton must
    // be up and the empty message must NOT have flashed first. (The fetch
    // itself is left in flight: refreshNovel catches all errors, and the
    // teardown below unmounts before it can touch the tree.)
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('No chapters available.'), findsNothing);
    }
    expect(find.byType(ShimmerChapterTile), findsWidgets);
    await _settleAndClose(tester, db);
  });

  testWidgets('failed fetch shows the failure empty-state', (tester) async {
    final id = await seedEmptyNovel();
    final router = GoRouter(
      initialLocation: '/novel/$id',
      routes: [
        GoRoute(
          path: '/novel/:id',
          builder: (_, state) => NovelDetailScreen(
            novelId: int.parse(state.pathParameters['id'] ?? '0'),
          ),
        ),
        GoRoute(
          path: '/reader/:novelId/:chapterId',
          builder: (_, _) => _stub('reader'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          appPrefsProvider.overrideWithValue(prefs),
          // Fail the fetch deterministically instead of hitting network:
          // empty + failed must show retry UI, never the skeleton.
          novelFetchStateProvider(
            id,
          ).overrideWith(() => _FailedFetchNotifier()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Could not load chapters.'), findsOneWidget);
    expect(find.byType(ShimmerChapterTile), findsNothing);
    await _settleAndClose(tester, db);
  });

  testWidgets('empty local novel shows the empty state, no fetch', (
    tester,
  ) async {
    final id = await seedEmptyNovel(providerId: 'local');
    await pumpNovel(tester, id);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    // Imports have no remote source: honest empty state, and no
    // refresh-failure snackbar from a fetch that must never run.
    expect(find.text('No chapters available.'), findsOneWidget);
    expect(find.text('Refresh failed'), findsNothing);
    await _settleAndClose(tester, db);
  });

  /// First chapter row's title, by vertical position. Chapter rows are dense
  /// InkWell rows rather than ListTiles, so order is read from geometry.
  String firstChapterTitle(WidgetTester tester) {
    const seeded = [
      'Plain Chapter',
      'Downloaded Chapter',
      'Read Chapter',
      'Bookmarked Chapter',
    ];
    double? top;
    String? name;
    for (final label in seeded) {
      final finder = find.text(label);
      if (finder.evaluate().isEmpty) continue;
      final y = tester.getTopLeft(finder.first).dy;
      if (top == null || y < top) {
        top = y;
        name = label;
      }
    }
    return name ?? '';
  }

  testWidgets('sort menu offers Normal, Chapter number, Latest first', (
    tester,
  ) async {
    await _pumpDetail(tester, db, prefs);
    // Seeded provider order: Plain, Downloaded, Read, Bookmarked.
    expect(firstChapterTitle(tester), 'Plain Chapter');

    await tester.tap(find.byKey(const ValueKey('chapter-sort')));
    await tester.pumpAndSettle();
    for (final label in ['Normal', 'Chapter number', 'Latest first']) {
      expect(find.text(label), findsOneWidget);
    }
    // No alphabetic sorts anymore.
    expect(find.text('Name A→Z'), findsNothing);

    await tester.tap(find.text('Latest first'));
    await tester.pumpAndSettle();
    expect(firstChapterTitle(tester), 'Bookmarked Chapter');
    await _settleAndClose(tester, db);
  });

  group('header actions', () {
    testWidgets('library and source are labelled pills beside the cover', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);

      // Icon + label, not a bare glyph: a lone filled heart reads as a status
      // badge and never says what pressing it does.
      expect(find.text('Add to library'), findsOneWidget);
      expect(find.text('Web View'), findsOneWidget);
      expect(find.byTooltip('Add to library'), findsOneWidget);
      expect(find.byTooltip('Open source page in Web View'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.public), findsOneWidget);

      // "Soon" was a dead button whose onTap was `() {}` — it looked
      // actionable and did nothing.
      expect(find.text('Soon'), findsNothing);
      expect(find.byIcon(Icons.hourglass_empty), findsNothing);

      await _settleAndClose(tester, db);
    });

    testWidgets('overflow holds select, refresh and Cloudflare only', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);

      await tester.tap(find.byKey(const ValueKey('novel-overflow')));
      await tester.pumpAndSettle();

      expect(find.text('Select chapters'), findsOneWidget);
      expect(find.text('Refresh details'), findsOneWidget);
      expect(find.text('Verify Cloudflare challenge'), findsOneWidget);

      // Chapter bulk actions do not live in the novel overflow.
      expect(find.text('Download selected'), findsNothing);
      expect(find.text('Select all'), findsNothing);

      await _settleAndClose(tester, db);
    });
  });

  group('chapter selection', () {
    Future<void> enterSelection(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('novel-overflow')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select chapters'));
      await tester.pumpAndSettle();
    }

    Future<void> openBulkMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('bulk-actions')));
      await tester.pumpAndSettle();
    }

    const bulkVerbs = [
      'Select all',
      'Download',
      'Bookmark',
      'Unmark',
      'Mark read',
      'Mark unread',
    ];

    testWidgets(
      'selection arms with zero picks and keeps the bar to two controls',
      (tester) async {
        await _pumpDetail(tester, db, prefs);
        await enterSelection(tester);

        expect(find.text('0 selected'), findsOneWidget);
        // The bottom bar is Cancel + a way to the verbs. The verbs themselves
        // are not spread across it — six of them never fit a phone-width row.
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byKey(const ValueKey('bulk-actions')), findsOneWidget);
        for (final label in bulkVerbs) {
          expect(find.text(label), findsNothing, reason: '$label on the bar');
        }

        await openBulkMenu(tester);
        for (final label in bulkVerbs) {
          expect(find.text(label), findsOneWidget, reason: '$label missing');
        }

        // Nothing is picked yet, so the verbs that act on picks are inert —
        // their row has no handler rather than silently doing nothing.
        final downloadRow = tester.widget<InkWell>(
          find
              .ancestor(
                of: find.text('Download'),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(downloadRow.onTap, isNull);
        // Select all needs no picks, so it stays live.
        final selectAllRow = tester.widget<InkWell>(
          find
              .ancestor(
                of: find.text('Select all'),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(selectAllRow.onTap, isNotNull);

        await _settleAndClose(tester, db);
      },
    );

    testWidgets('opening the overflow menu does not overflow', (tester) async {
      await _pumpDetail(tester, db, prefs);
      // The popup items used to be Row[Icon, Text] with no flexible child,
      // so the menu overflowed its clamped route by ~150px at every width.
      await tester.tap(find.byKey(const ValueKey('novel-overflow')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Verify Cloudflare challenge'), findsOneWidget);
      await _settleAndClose(tester, db);
    });

    testWidgets('the selection bar does not overflow', (tester) async {
      await _pumpDetail(tester, db, prefs);
      await enterSelection(tester);
      expect(tester.takeException(), isNull);
      await _settleAndClose(tester, db);
    });

    testWidgets('tapping rows counts picks, select all fills the visible set', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);
      await enterSelection(tester);

      await tester.tap(find.text('Plain Chapter'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await openBulkMenu(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('4 selected'), findsOneWidget);

      // Once everything is picked the affordance flips to a clear action.
      await openBulkMenu(tester);
      expect(find.text('Select none'), findsOneWidget);
      await tester.tap(find.text('Select none'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);

      await _settleAndClose(tester, db);
    });

    testWidgets('bulk mark read and unread applies to the selection', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);
      await enterSelection(tester);
      await openBulkMenu(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      await openBulkMenu(tester);
      await tester.tap(find.text('Mark read'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      var chapters = await db.chapterDao.getChaptersForNovel(1);
      expect(chapters.where((c) => c.read).length, 4);

      // Bulk actions leave selection mode behind them.
      expect(find.text('0 selected'), findsNothing);
      expect(find.byKey(const ValueKey('bulk-actions')), findsNothing);

      await enterSelection(tester);
      await openBulkMenu(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await openBulkMenu(tester);
      await tester.tap(find.text('Mark unread'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      chapters = await db.chapterDao.getChaptersForNovel(1);
      expect(chapters.where((c) => c.read).length, 0);

      await _settleAndClose(tester, db);
    });

    testWidgets('bulk bookmark round-trips', (tester) async {
      await _pumpDetail(tester, db, prefs);
      await enterSelection(tester);
      await openBulkMenu(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      await openBulkMenu(tester);
      await tester.tap(find.text('Bookmark'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      var chapters = await db.chapterDao.getChaptersForNovel(1);
      expect(chapters.where((c) => c.bookmarked).length, 4);

      await enterSelection(tester);
      await openBulkMenu(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await openBulkMenu(tester);
      await tester.tap(find.text('Unmark'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      chapters = await db.chapterDao.getChaptersForNovel(1);
      expect(chapters.where((c) => c.bookmarked).length, 0);

      await _settleAndClose(tester, db);
    });

    testWidgets('a selection tap does not open the reader', (tester) async {
      await _pumpDetail(tester, db, prefs);
      await enterSelection(tester);

      await tester.tap(find.text('Plain Chapter'));
      await tester.pumpAndSettle();

      expect(find.text('reader'), findsNothing);
      expect(find.text('1 selected'), findsOneWidget);

      await _settleAndClose(tester, db);
    });

    testWidgets('cancel leaves selection mode', (tester) async {
      await _pumpDetail(tester, db, prefs);
      await enterSelection(tester);
      expect(find.text('0 selected'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('0 selected'), findsNothing);
      expect(find.text('Bookmark'), findsNothing);
      // The novel-level overflow is back, and the bulk menu is gone.
      expect(find.byKey(const ValueKey('novel-overflow')), findsOneWidget);
      expect(find.byKey(const ValueKey('bulk-actions')), findsNothing);

      await _settleAndClose(tester, db);
    });

    testWidgets('long press opens the chapter row menu', (tester) async {
      await _pumpDetail(tester, db, prefs);

      await tester.longPress(find.text('Plain Chapter'));
      await tester.pumpAndSettle();

      expect(find.text('Mark earlier as read'), findsOneWidget);
      expect(find.text('Select from here down'), findsOneWidget);
      expect(find.text('Bookmark'), findsOneWidget);
      // Long press no longer jumps straight into selection mode.
      expect(find.text('selected'), findsNothing);

      await _settleAndClose(tester, db);
    });

    testWidgets('download for one chapter lives in the row menu', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);

      // The per-row download button is gone: a hundred rows meant a hundred
      // near-identical glyphs, almost all of them saying "not downloaded".
      expect(find.byTooltip('Download chapter'), findsNothing);

      // Still reachable for a single chapter.
      await tester.longPress(find.text('Plain Chapter'));
      await tester.pumpAndSettle();
      expect(find.text('Download chapter'), findsOneWidget);

      // A chapter already on disk reports state instead of offering a second
      // download of the same file.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Downloaded Chapter'));
      await tester.pumpAndSettle();
      final doneTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Downloaded'),
      );
      expect(doneTile.enabled, isFalse);

      await _settleAndClose(tester, db);
    });

    testWidgets('mark earlier as read greys out everything before', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);

      // The cross-provider resume case: 3 chapters already read, the reader
      // restarts on the 4th in a source that carries more.
      await tester.longPress(find.text('Bookmarked Chapter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark earlier as read'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      final chapters = await db.chapterDao.getChaptersForNovel(1);
      for (final c in chapters.where((c) => c.index < 3)) {
        expect(c.read, isTrue, reason: 'chapter ${c.index} should be read');
      }
      // The chapter acted on and everything after it are untouched.
      expect(chapters.firstWhere((c) => c.index == 3).read, isFalse);

      await _settleAndClose(tester, db);
    });

    testWidgets('select from here down arms selection with the tail', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);

      await tester.longPress(find.text('Read Chapter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select from here down'));
      await tester.pumpAndSettle();

      // Seeded order: Plain(0), Downloaded(1), Read(2), Bookmarked(3).
      expect(find.text('2 selected'), findsOneWidget);

      await _settleAndClose(tester, db);
    });

    testWidgets('mark earlier is a no-op on the first chapter', (tester) async {
      await _pumpDetail(tester, db, prefs);

      await tester.longPress(find.text('Plain Chapter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark earlier as read'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing before this chapter'), findsOneWidget);

      await _settleAndClose(tester, db);
    });
  });
}
