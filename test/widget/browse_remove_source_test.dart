import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noveldock/core/config/app_prefs.dart';
import 'package:noveldock/core/database/database.dart';
import 'package:noveldock/core/providers/database_providers.dart';
import 'package:noveldock/core/providers/models.dart';
import 'package:noveldock/core/providers/registries.dart';
import 'package:noveldock/features/browse/browse_screen.dart';

Widget _stub(String label) => Scaffold(body: Center(child: Text(label)));

const _installed = ProviderMeta(
  id: 'wuxiabox',
  name: 'WuxiaBox',
  lang: 'zh',
  baseUrl: 'https://www.wuxiabox.com',
  file: 'wuxiabox.js',
  version: '1.0.0',
);

const _available = ProviderMeta(
  id: 'wuxiaworld',
  name: 'WuxiaWorld',
  lang: 'en',
  baseUrl: 'https://www.wuxiaworld.com',
  file: 'wuxiaworld.js',
  version: '1.0.0',
);

/// Pump Browse with one installed and one not-installed source.
///
/// The installed set is seeded through the real settings table rather than an
/// override, so the test exercises the same persistence the app uses — and so
/// a "removed" source that only vanished from the widget tree would fail.
Future<ProviderContainer> _pumpBrowse(
  WidgetTester tester,
  AppDatabase db,
  SharedPreferences prefs,
) async {
  final router = GoRouter(
    initialLocation: '/browse',
    routes: [
      GoRoute(path: '/browse', builder: (_, _) => const BrowseScreen()),
      GoRoute(path: '/provider/:id', builder: (_, _) => _stub('provider')),
      GoRoute(path: '/settings/providers', builder: (_, _) => _stub('regs')),
    ],
  );
  addTearDown(router.dispose);

  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      appPrefsProvider.overrideWithValue(prefs),
      availableProvidersProvider.overrideWith(
        (ref) async => const [_installed, _available],
      ),
    ],
  );
  addTearDown(container.dispose);

  await db
      .into(db.settings)
      .insert(
        SettingsCompanion.insert(
          key: 'enabled_providers',
          value: '["wuxiabox"]',
        ),
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // No pumpAndSettle: shimmer placeholders animate forever while visible.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }

  return container;
}

/// Advance past route animations.
///
/// Popup menus and dialogs animate in over a couple of frames; a single pump
/// can leave the target mid-flight and therefore untappable.
Future<void> _pumpUi(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Switch to the Catalog tab, where every source and both verbs live.
Future<void> _openCatalog(WidgetTester tester) async {
  await tester.tap(find.text('Catalog'));
  await _pumpUi(tester);
}

/// The Uninstall button on [name]'s Catalog row.
///
/// Scoped to the row on purpose: the confirm dialog labels its action
/// "Uninstall" too, and tapping the row itself would open the details sheet
/// over the button.
Finder _rowButton(String name, String label) {
  return find.descendant(
    of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
    matching: find.widgetWithText(TextButton, label),
  );
}

/// Uninstall [name] from the Catalog and confirm the dialog.
Future<void> _uninstall(WidgetTester tester, String name) async {
  await tester.tap(_rowButton(name, 'Uninstall'));
  await _pumpUi(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
  await _pumpUi(tester);
}

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  // The Catalog used to hide installed sources, so tapping a row installed it
  // and the row vanished — and the reverse verb existed nowhere in the app.
  // Both verbs now live on the row, spelled out.
  testWidgets('catalog shows both verbs, one per source state', (tester) async {
    final container = await _pumpBrowse(tester, db, prefs);

    await _openCatalog(tester);

    expect(find.text('WuxiaBox'), findsOneWidget);
    expect(find.text('WuxiaWorld'), findsOneWidget);

    // Installed row offers Uninstall, the other offers Install.
    expect(_rowButton('WuxiaBox', 'Uninstall'), findsOneWidget);
    expect(_rowButton('WuxiaWorld', 'Install'), findsOneWidget);

    expect(container.read(enabledProvidersProvider), contains('wuxiabox'));

    await _settleAndClose(tester, db);
  });

  testWidgets('uninstalling keeps the row and flips it back to Install', (
    tester,
  ) async {
    final container = await _pumpBrowse(tester, db, prefs);

    await _openCatalog(tester);
    await _uninstall(tester, 'WuxiaBox');

    // The row stays in the list — it is the only place either verb exists.
    expect(find.text('WuxiaBox'), findsOneWidget);
    expect(_rowButton('WuxiaBox', 'Install'), findsOneWidget);

    expect(
      container.read(enabledProvidersProvider),
      isNot(contains('wuxiabox')),
    );
    expect(find.textContaining('Uninstalled WuxiaBox'), findsOneWidget);

    await _settleAndClose(tester, db);
  });

  testWidgets('uninstall asks first, and cancelling changes nothing', (
    tester,
  ) async {
    final container = await _pumpBrowse(tester, db, prefs);

    await _openCatalog(tester);
    await tester.tap(_rowButton('WuxiaBox', 'Uninstall'));
    await _pumpUi(tester);

    expect(find.text('Uninstall WuxiaBox?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await _pumpUi(tester);

    expect(container.read(enabledProvidersProvider), contains('wuxiabox'));

    await _settleAndClose(tester, db);
  });

  testWidgets('undo reinstalls the source', (tester) async {
    final container = await _pumpBrowse(tester, db, prefs);

    await _openCatalog(tester);
    await _uninstall(tester, 'WuxiaBox');

    expect(
      container.read(enabledProvidersProvider),
      isNot(contains('wuxiabox')),
    );

    await tester.tap(find.text('Undo'));
    await _pumpUi(tester);

    expect(container.read(enabledProvidersProvider), contains('wuxiabox'));

    await _settleAndClose(tester, db);
  });

  testWidgets('uninstall persists to the settings table', (tester) async {
    await _pumpBrowse(tester, db, prefs);

    await _openCatalog(tester);
    await _uninstall(tester, 'WuxiaBox');

    // The card in the Installed tab is gone with the source; the setting must
    // not come back with it. This is what the container-based setProviderEnabled
    // exists for — an Undo tapped after the owning widget is gone.
    final stored = await db.select(db.settings).getSingleOrNull();

    expect(stored?.value, isNot(contains('wuxiabox')));

    await _settleAndClose(tester, db);
  });

  testWidgets('the Installed card offers no hidden overflow menu', (
    tester,
  ) async {
    await _pumpBrowse(tester, db, prefs);

    // Browse opens on Installed. The three dots were tried and rejected: they
    // put uninstall one tap deeper than the tap that installed the source.
    expect(find.text('WuxiaBox'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);

    await _settleAndClose(tester, db);
  });
}

/// See library_screen_test.dart: unmount + flush drift close timers in-test.
Future<void> _settleAndClose(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(Container());
  await tester.pump(const Duration(milliseconds: 200));
  await db.close();
  await tester.pump(const Duration(milliseconds: 200));
}
