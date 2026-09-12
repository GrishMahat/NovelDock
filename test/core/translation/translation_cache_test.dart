import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/translation/translation_service.dart';

// Pins the exactness contract of the translation cache key: two texts that
// share a long prefix must never collide (the old prefix-100-chars key
// served one chapter's translation for another).
void main() {
  test('same text and langs produce the same key', () {
    expect(
      TranslationService.cacheKey('hello world', 'en', 'ru'),
      TranslationService.cacheKey('hello world', 'en', 'ru'),
    );
  });

  test('texts sharing a 100+ char prefix produce different keys', () {
    final prefix = List.filled(20, 'lorem ipsum dolor sit amet ').join();
    expect(prefix.length, greaterThan(100));
    final a = TranslationService.cacheKey('${prefix}ending one', 'en', 'ru');
    final b = TranslationService.cacheKey('${prefix}ending two', 'en', 'ru');
    expect(a, isNot(equals(b)));
  });

  test('different language pairs produce different keys', () {
    expect(
      TranslationService.cacheKey('same text', 'en', 'ru'),
      isNot(equals(TranslationService.cacheKey('same text', 'en', 'fr'))),
    );
  });
}
