import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/widgets/novel_card.dart';

void main() {
  group('formatRating', () {
    test('stars divide by 200', () {
      expect(formatRating(850, 'stars'), '4.3');
      expect(formatRating(1000, 'stars'), '5');
      expect(formatRating(0, 'stars'), '0');
    });

    test('ten divides by 100', () {
      expect(formatRating(850, 'ten'), '8.5');
      expect(formatRating(1000, 'ten'), '10');
    });

    test('hundred divides by 10', () {
      expect(formatRating(850, 'hundred'), '85');
      expect(formatRating(855, 'hundred'), '85.5');
    });

    test('unknown format falls back to stars', () {
      expect(formatRating(600, 'bogus'), '3');
    });
  });
}
