import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/tts/engine/system_tts_engine.dart';

void main() {
  group('normalizeAndroidTtsLocale', () {
    test('converts 3-letter Android tags to BCP-47', () {
      expect(normalizeAndroidTtsLocale('eng-USA'), 'en-US');
      expect(normalizeAndroidTtsLocale('rus-RUS'), 'ru-RU');
      expect(normalizeAndroidTtsLocale('ukr-UKR'), 'uk-UA');
      expect(normalizeAndroidTtsLocale('zho-CHN'), 'zh-CN');
    });

    test('passes through already-2-letter tags with region uppercased', () {
      expect(normalizeAndroidTtsLocale('en-US'), 'en-US');
      expect(normalizeAndroidTtsLocale('pt-br'), 'pt-BR');
    });

    test('normalizes script subtags', () {
      expect(normalizeAndroidTtsLocale('zho-Hans-CN'), 'zh-Hans-CN');
    });

    test('unknown language codes survive unchanged apart from casing', () {
      expect(normalizeAndroidTtsLocale('xyz-US'), 'xyz-US');
    });

    test('handles bare and empty tags', () {
      expect(normalizeAndroidTtsLocale('eng'), 'en');
      expect(normalizeAndroidTtsLocale(''), '');
      expect(normalizeAndroidTtsLocale('  eng-usa  '), 'en-US');
    });
  });
}
