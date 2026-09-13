import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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
            read: Value(read),
            bookmarked: Value(bookmarked),
          ),
        );
    await chapter('Plain Chapter', 0);
    await chapter('Downloaded Chapter', 1, downloaded: true);
    await chapter('Read Chapter', 2, read: true);
    await chapter('Bookmarked Chapter', 3, bookmarked: true);
  });

  // DB is closed per-test via _settleAndClose (see above); nothing here.

  testWidgets('filter chips render with the chapter count', (tester) async {
    await _pumpDetail(tester, db, prefs);
    expect(find.text('4 chapters'), findsOneWidget);
    for (final label in ['All', 'Downloaded', 'Bookmarked', 'Read', 'Unread']) {
      expect(find.widgetWithText(FilterChip, label), findsOneWidget);
    }
    await _settleAndClose(tester, db);
  });

  testWidgets('Downloaded filter narrows the list', (tester) async {
    await _pumpDetail(tester, db, prefs);
    await tester.tap(find.widgetWithText(FilterChip, 'Downloaded'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('1 of 4 chapters'), findsOneWidget);
    expect(find.text('Downloaded Chapter'), findsOneWidget);
    expect(find.text('Plain Chapter'), findsNothing);
    await _settleAndClose(tester, db);
  });

  testWidgets('Unread filter excludes read chapters', (tester) async {
    await _pumpDetail(tester, db, prefs);
    await tester.tap(find.widgetWithText(FilterChip, 'Unread'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('3 of 4 chapters'), findsOneWidget);
    expect(find.text('Read Chapter'), findsNothing);
    expect(find.text('Plain Chapter'), findsOneWidget);
    await _settleAndClose(tester, db);
  });

  testWidgets('Bookmarked filter shows only bookmarked', (tester) async {
    await _pumpDetail(tester, db, prefs);
    await tester.tap(find.widgetWithText(FilterChip, 'Bookmarked'));
    await tester.pump(const Duration(milliseconds: 200));

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

  String firstChapterTitle(WidgetTester tester) {
    final first = tester.widgetList<ListTile>(find.byType(ListTile)).first;
    return (first.title as Text).data ?? '';
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
}
