import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noveldock/core/config/app_prefs.dart';
import 'package:noveldock/core/database/database.dart';
import 'package:noveldock/core/providers/database_providers.dart';
import 'package:noveldock/features/library/library_screen.dart';

Widget _stub(String label) => Scaffold(body: Center(child: Text(label)));

Future<SharedPreferences> _mockPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Future<void> _pumpLibrary(
  WidgetTester tester,
  AppDatabase db,
  SharedPreferences prefs,
) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
      GoRoute(path: '/browse', builder: (_, _) => _stub('browse')),
      GoRoute(path: '/novel/:id', builder: (_, _) => _stub('novel')),
      GoRoute(path: '/import', builder: (_, _) => _stub('import')),
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
  // No pumpAndSettle: shimmer placeholders animate forever while visible,
  // so settle would never complete. Fixed pumps flush the DB streams.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Unmount the tree and flush drift's stream-close timers BEFORE the test
/// ends: flutter_test runs in a fake-async zone where drift's zero-duration
/// close timer would otherwise trip the pending-timer invariant at teardown.
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
    prefs = await _mockPrefs();
  });

  // DB is closed per-test via _settleAndClose (see above); nothing here.

  Future<int> seedLibraryNovel(String title) async {
    final id = await db
        .into(db.novels)
        .insert(
          NovelsCompanion.insert(
            providerId: 'test',
            url: 'https://example.com/$title',
            title: title,
            addedAt: 1,
          ),
        );
    await db.libraryDao.addToLibrary(id, status: 'Reading');
    return id;
  }

  testWidgets('empty library shows empty state', (tester) async {
    await _pumpLibrary(tester, db, prefs);
    expect(find.text('No novels saved yet'), findsOneWidget);
    expect(find.text('Browse sources'), findsOneWidget);
    await _settleAndClose(tester, db);
  });

  testWidgets('seeded novel appears in the list', (tester) async {
    await seedLibraryNovel('My Novel');
    await _pumpLibrary(tester, db, prefs);
    expect(find.text('My Novel'), findsOneWidget);
    await _settleAndClose(tester, db);
  });

  testWidgets('search field narrows the list', (tester) async {
    await seedLibraryNovel('Alpha Novel');
    await seedLibraryNovel('Beta Novel');
    await _pumpLibrary(tester, db, prefs);
    expect(find.text('Alpha Novel'), findsOneWidget);
    expect(find.text('Beta Novel'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Alpha Novel'), findsOneWidget);
    expect(find.text('Beta Novel'), findsNothing);
    await _settleAndClose(tester, db);
  });
}
