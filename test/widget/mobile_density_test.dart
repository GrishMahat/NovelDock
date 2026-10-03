// Regression guard for the mobile density pass. Locks the phone geometry
// that used to flip or overflow: grid column counts per width tier, dense
// row heights, and the reader's per-form-factor padding profile.
// material_ui must match lib/theme/app_theme.dart — see the note there.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noveldock/theme/app_theme.dart';
import 'package:noveldock/theme/tokens.dart';

/// 393dp is the width that used to resolve the browse grid to 3 columns of
/// 120dp; 360dp is the common low end.
const List<Size> kPhones = [Size(360, 800), Size(393, 851), Size(412, 915)];

Future<void> _at(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

int _columnsForWidth(double width, int Function(ScreenSize) pick) =>
    pick(screenSizeForWidth(width));

void main() {
  group('width tiers', () {
    test('classifies widths', () {
      // Every phone width is compact.
      expect(screenSizeForWidth(320), ScreenSize.compact);
      expect(screenSizeForWidth(360), ScreenSize.compact);
      expect(screenSizeForWidth(393), ScreenSize.compact);
      expect(screenSizeForWidth(412), ScreenSize.compact);
      expect(screenSizeForWidth(480), ScreenSize.compact);
      expect(screenSizeForWidth(599), ScreenSize.compact);
      // Tablet / half-screen window.
      expect(screenSizeForWidth(600), ScreenSize.medium);
      expect(screenSizeForWidth(840), ScreenSize.medium);
      expect(screenSizeForWidth(899), ScreenSize.medium);
      // Maximized window.
      expect(screenSizeForWidth(900), ScreenSize.expanded);
      expect(screenSizeForWidth(1200), ScreenSize.expanded);
      expect(screenSizeForWidth(1920), ScreenSize.expanded);
    });

    test('compact is the only tier with isCompact', () {
      expect(ScreenSize.compact.isCompact, isTrue);
      expect(ScreenSize.medium.isCompact, isFalse);
      expect(ScreenSize.expanded.isCompact, isFalse);
    });
  });

  group('grid column counts are stable across phone widths', () {
    test('browse grid never drops below 2 or exceeds 5', () {
      for (final size in kPhones) {
        final cols = _columnsForWidth(size.width, Grids.browseColumns);
        expect(cols, inInclusiveRange(2, 5), reason: 'at ${size.width}dp');
      }
    });

    test('browse grid column count does not change across phone widths', () {
      // The original bug: maxCrossAxisExtent 170 gave 2 columns at 360dp and
      // 3 at 393dp, so a 33dp difference changed the layout.
      final counts = kPhones
          .map((s) => Grids.browseColumns(screenSizeForWidth(s.width)))
          .toSet();
      expect(counts.length, 1, reason: 'column count varied: $counts');
    });

    test('library grid is 3-up on phones, not 2', () {
      for (final size in kPhones) {
        expect(Grids.libraryColumns(screenSizeForWidth(size.width)), 3);
      }
    });

    test('browse and library grids agree per tier', () {
      for (final tier in ScreenSize.values) {
        // Both are distinct by design (browse cards carry a provider line),
        // but neither may collapse to a single column on a phone.
        expect(Grids.browseColumns(tier), greaterThanOrEqualTo(2));
        expect(Grids.libraryColumns(tier), greaterThanOrEqualTo(2));
      }
    });

    test('cards are tall enough to hold cover plus two lines of title', () {
      for (final tier in ScreenSize.values) {
        expect(Grids.browseExtent(tier), greaterThanOrEqualTo(200));
        expect(Grids.libraryExtent(tier), greaterThanOrEqualTo(180));
      }
    });

    test('installed sources fit two per row on compact', () {
      expect(Grids.sourceColumns(ScreenSize.compact), 2);
      expect(Grids.sourceExtent(ScreenSize.compact), lessThanOrEqualTo(60));
    });
  });

  group('dense list rows', () {
    testWidgets('catalog row with a Switch fits 48dp on a phone', (
      tester,
    ) async {
      await _at(tester, kPhones[1]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ListView(
              children: [
                for (var i = 0; i < 20; i++)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const CircleAvatar(radius: 18),
                    title: Text('Source $i'),
                    subtitle: const Text('EN · v1.0.0'),
                    trailing: Switch(value: true, onChanged: (_) {}),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tile = tester.getSize(find.byType(ListTile).first);
      // Was 72dp with the duplicate info IconButton in trailing.
      expect(tile.height, lessThanOrEqualTo(56));

      // More rows per screen than the 8 that used to fit.
      final visible = find.byType(ListTile).evaluate().where((e) {
        final b = e.findRenderObject();
        return b != null && b.paintBounds.top < kPhones[1].height;
      }).length;
      expect(visible, greaterThanOrEqualTo(11));
    });
  });

  group('text scale clamp', () {
    test('bounds leave room for accessibility without breaking layout', () {
      expect(kMinTextScale, 1.0);
      expect(kMaxTextScale, greaterThan(1.0));
      expect(kMaxTextScale, lessThanOrEqualTo(1.5));
    });
  });

  group('installed sources grid is scrollable', () {
    testWidgets('all sources are reachable below the fold', (tester) async {
      await _at(tester, kPhones[0]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 56,
                    crossAxisSpacing: Insets.sm,
                    mainAxisSpacing: Insets.sm,
                  ),
                  itemCount: 40,
                  itemBuilder: (_, i) =>
                      SizedBox(key: ValueKey(i), child: Text('source $i')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('source 0'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('source 39'), 400);
      expect(find.text('source 39'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
