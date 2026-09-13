import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/providers/models.dart';
import 'package:noveldock/core/utils/incoming_intent.dart';

ProviderMeta _meta(String id, String baseUrl) => ProviderMeta(
  id: id,
  name: id,
  lang: 'en',
  baseUrl: baseUrl,
  file: '$id.js',
  version: '1.0.0',
);

void main() {
  final metas = [
    _meta('wuxiabox', 'https://www.wuxiabox.com'),
    _meta('royalroad', 'https://www.royalroad.com'),
  ];

  group('IncomingIntent.matchProviderForUrl', () {
    test('matches exact and www-variant hosts', () {
      expect(
        IncomingIntent.matchProviderForUrl(
          'https://www.wuxiabox.com/novel/123',
          metas,
        ),
        'wuxiabox',
      );
      expect(
        IncomingIntent.matchProviderForUrl(
          'https://wuxiabox.com/novel/123',
          metas,
        ),
        'wuxiabox',
      );
    });

    test('matches sub-paths and query strings', () {
      expect(
        IncomingIntent.matchProviderForUrl(
          'https://www.royalroad.com/fiction/12345/some-novel?x=1',
          metas,
        ),
        'royalroad',
      );
    });

    test('unknown hosts yield null', () {
      expect(
        IncomingIntent.matchProviderForUrl(
          'https://unknown-site.example/novel/1',
          metas,
        ),
        isNull,
      );
    });

    test('prevents suffix-confusion attacks', () {
      expect(
        IncomingIntent.matchProviderForUrl(
          'https://evilwuxiabox.com/novel/1',
          metas,
        ),
        isNull,
      );
    });

    test('garbage urls yield null instead of throwing', () {
      expect(IncomingIntent.matchProviderForUrl('not a url', metas), isNull);
      expect(IncomingIntent.matchProviderForUrl('', metas), isNull);
    });
  });
}
