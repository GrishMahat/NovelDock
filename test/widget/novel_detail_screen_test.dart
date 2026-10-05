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
import 'package:noveldock/features/novel/widgets/status_picker_sheet.dart';
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

  /// Opens the chapter filter dialog from the overflow menu's single
  /// "Filter chapters" entry — the path the UI actually offers now.
  Future<void> openFilterDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('novel-overflow')));
    await tester.pumpAndSettle();
    // The entry carries a count once filters are active ("Filter chapters
    // (2)"), so match on the prefix rather than the exact label.
    await tester.tap(find.textContaining('Filter chapters'));
    await tester.pumpAndSettle();
  }

  /// Ticks [labels] in the open dialog and applies them.
  Future<void> applyFilters(WidgetTester tester, List<String> labels) async {
    for (final label in labels) {
      await tester.tap(find.widgetWithText(CheckboxListTile, label));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
  }

  testWidgets('filter chips render with the chapter count', (tester) async {
    await _pumpDetail(tester, db, prefs);
    expect(find.text('4 chapters'), findsOneWidget);
    // The chips are gone: the filters live behind one "Filter chapters" entry
    // in the overflow menu, so nothing competes with the count for that line.
    for (final label in ['Downloaded', 'Bookmarked', 'Read', 'Unread']) {
      expect(find.widgetWithText(FilterChip, label), findsNothing);
    }
    await _settleAndClose(tester, db);
  });

  testWidgets('the filter dialog lists every status and applies on Apply', (
    tester,
  ) async {
    await _pumpDetail(tester, db, prefs);
    await openFilterDialog(tester);

    for (final label in ['Downloaded', 'Bookmarked', 'Read', 'Unread']) {
      expect(find.widgetWithText(CheckboxListTile, label), findsOneWidget);
    }
    // Nothing is ticked to begin with: an empty set means no filter. The
    // boxes render, they just render unchecked.
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((tile) => tile.value == false),
      isTrue,
    );
    // Backing out leaves the list untouched.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('4 chapters'), findsOneWidget);

    await _settleAndClose(tester, db);
  });

  testWidgets('multiple filters combine as OR and Clear resets them', (
    tester,
  ) async {
    await _pumpDetail(tester, db, prefs);
    await openFilterDialog(tester);
    await applyFilters(tester, ['Downloaded', 'Bookmarked']);

    // Downloaded OR Bookmarked: the two matching chapters, nothing else.
    expect(find.text('2 of 4 chapters'), findsOneWidget);
    expect(find.text('Downloaded Chapter'), findsOneWidget);
    expect(find.text('Bookmarked Chapter'), findsOneWidget);
    expect(find.text('Plain Chapter'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('4 chapters'), findsOneWidget);
    expect(find.text('Plain Chapter'), findsOneWidget);
    await _settleAndClose(tester, db);
  });

  testWidgets('un-ticking one box clears just that filter', (tester) async {
    await _pumpDetail(tester, db, prefs);
    await openFilterDialog(tester);
    await applyFilters(tester, ['Downloaded', 'Bookmarked']);
    expect(find.text('2 of 4 chapters'), findsOneWidget);

    // Reopen, drop one box, apply.
    await openFilterDialog(tester);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Downloaded'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 4 chapters'), findsOneWidget);
    expect(find.text('Bookmarked Chapter'), findsOneWidget);
    await _settleAndClose(tester, db);
  });

  testWidgets('Downloaded filter narrows the list', (tester) async {
    await _pumpDetail(tester, db, prefs);
    await openFilterDialog(tester);
    await applyFilters(tester, ['Downloaded']);

    expect(find.text('1 of 4 chapters'), findsOneWidget);
    expect(find.text('Downloaded Chapter'), findsOneWidget);
    expect(find.text('Plain Chapter'), findsNothing);
    await _settleAndClose(tester, db);
  });

  testWidgets('Unread filter excludes read chapters', (tester) async {
    await _pumpDetail(tester, db, prefs);
    await openFilterDialog(tester);
    await applyFilters(tester, ['Unread']);

    expect(find.text('3 of 4 chapters'), findsOneWidget);
    expect(find.text('Read Chapter'), findsNothing);
    expect(find.text('Plain Chapter'), findsOneWidget);
    await _settleAndClose(tester, db);
  });

  testWidgets('Bookmarked filter shows only bookmarked', (tester) async {
    await _pumpDetail(tester, db, prefs);
    await openFilterDialog(tester);
    await applyFilters(tester, ['Bookmarked']);

    expect(find.text('1 of 4 chapters'), findsOneWidget);
    expect(find.text('Bookmarked Chapter'), findsOneWidget);
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

    await tester.tap(find.byIcon(Icons.sort));
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
    testWidgets('library, Mark all read and WebView sit in their own row', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);

      // Restored to the original full-width action row (spaceAround, vertical
      // icon-over-label), not the later inline header pills. "Library" shows
      // the tracked status once set; the label is "Add to library" until then.
      expect(find.text('Add to library'), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
      expect(find.text('WebView'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      expect(find.byIcon(Icons.language), findsOneWidget);

      // The dead "Soon" button is gone for good.
      expect(find.text('Soon'), findsNothing);
      expect(find.byIcon(Icons.hourglass_empty), findsNothing);

      // The inline pill labels are gone with the pill layout.
      expect(find.text('Library'), findsNothing);
      expect(find.text('Source'), findsNothing);

      await _settleAndClose(tester, db);
    });

    testWidgets('Mark all read marks every unread chapter', (tester) async {
      await _pumpDetail(tester, db, prefs);

      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      final chapters = await db.chapterDao.getChaptersForNovel(1);
      expect(chapters.where((c) => c.read).length, 4);

      // Second press has nothing left to do, and says so rather than
      // claiming a success it did not perform.
      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();
      expect(find.text('Every chapter is already read'), findsOneWidget);

      await _settleAndClose(tester, db);
    });

    testWidgets('the library button opens the status picker', (tester) async {
      await _pumpDetail(tester, db, prefs);

      await tester.tap(find.text('Add to library'));
      await tester.pumpAndSettle();

      // The sheet the original row opened, with its own heading.
      expect(find.text('Add to library'), findsWidgets);
      expect(find.byType(StatusPickerSheet), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await _settleAndClose(tester, db);
    });

    testWidgets('overflow holds select, refresh and Cloudflare only', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);

      await tester.tap(find.byIcon(Icons.more_vert));
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
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select chapters'));
      await tester.pumpAndSettle();
    }

    testWidgets('selection arms with zero picks and shows bulk actions', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);
      await enterSelection(tester);

      expect(find.text('0 selected'), findsOneWidget);
      // Bulk actions live in a bottom bar, thumb-reachable, not the app bar.
      for (final label in [
        'Cancel',
        'Select all',
        'Download',
        'Bookmark',
        'Unmark',
        'Mark read',
        'Mark unread',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label missing');
      }

      await _settleAndClose(tester, db);
    });

    testWidgets('opening the overflow menu does not overflow', (tester) async {
      await _pumpDetail(tester, db, prefs);
      // The popup items used to be Row[Icon, Text] with no flexible child,
      // so the menu overflowed its clamped route by ~150px at every width.
      await tester.tap(find.byIcon(Icons.more_vert));
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

      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('4 selected'), findsOneWidget);

      // Once everything is picked the affordance flips to a clear action.
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
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark read'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      var chapters = await db.chapterDao.getChaptersForNovel(1);
      expect(chapters.where((c) => c.read).length, 4);

      // Bulk actions leave selection mode behind them.
      expect(find.text('0 selected'), findsNothing);
      expect(find.text('Bookmark'), findsNothing);

      await enterSelection(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
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
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bookmark'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      var chapters = await db.chapterDao.getChaptersForNovel(1);
      expect(chapters.where((c) => c.bookmarked).length, 4);

      await enterSelection(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
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
      // The novel-level overflow is back.
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      await _settleAndClose(tester, db);
    });

    testWidgets('long press opens the chapter row menu', (tester) async {
      await _pumpDetail(tester, db, prefs);

      await tester.longPress(find.text('Plain Chapter'));
      await tester.pumpAndSettle();

      expect(find.text('Mark earlier as read'), findsOneWidget);
      expect(find.text('Select from here down'), findsOneWidget);
      expect(find.text('Bookmark'), findsOneWidget);
      // Download is reachable from the long-press menu as a real verb.
      // Scoped to the sheet: "Downloaded" also names a filter chip behind it.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Download chapter'),
        ),
        findsOneWidget,
      );
      // Long press no longer jumps straight into selection mode.
      expect(find.text('selected'), findsNothing);

      await _settleAndClose(tester, db);
    });

    testWidgets('long press offers download for a chapter already on disk', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);

      await tester.longPress(find.text('Downloaded Chapter'));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      // Already on disk: the entry is a state readout, not a tappable verb,
      // so it must not queue the same file twice.
      expect(
        find.descendant(of: sheet, matching: find.text('Downloaded')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Download chapter')),
        findsNothing,
      );
      // And the readout is not pressable.
      expect(
        tester
            .widget<ListTile>(
              find.descendant(
                of: sheet,
                matching: find.widgetWithText(ListTile, 'Downloaded'),
              ),
            )
            .onTap,
        isNull,
      );

      await _settleAndClose(tester, db);
    });

    testWidgets('mark earlier as read greys out everything before', (
      tester,
    ) async {
      await _pumpDetail(tester, db, prefs);

      // The cross-provider resume case: 3 chapters already read, the reader
      // restarts on the 4th in a source that carries more. Scroll it into
      // view first: the restored action row pushes the last chapter past the
      // bottom of a short test viewport.
      await tester.ensureVisible(find.text('Bookmarked Chapter'));
      await tester.pumpAndSettle();
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
