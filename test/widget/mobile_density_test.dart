// Regression guard for the mobile density pass. Locks the grid column
// counts per width tier — the geometry that used to flip between phone
// widths (2 columns at 360dp vs 3 at 393dp).
// material_ui must match lib/theme/app_theme.dart — see the note there.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noveldock/theme/tokens.dart';

/// 393dp is the width that used to resolve the browse grid to 3 columns of
/// 120dp; 360dp is the common low end.
const List<Size> kPhones = [Size(360, 800), Size(393, 851), Size(412, 915)];

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
}
