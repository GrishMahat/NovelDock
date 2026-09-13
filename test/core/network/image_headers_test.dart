import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/network/client.dart';
import 'package:noveldock/core/network/image_headers.dart';

/// Probe calling the helper with a real [Ref] inside the test container.
final _probeProvider = FutureProvider.family<Map<String, String>, String>(
  (ref, url) => imageHeadersForUrl(url, ref),
);

ProviderContainer _containerWith(CookieJar jar) {
  return ProviderContainer(
    overrides: [cookieJarProvider.overrideWith((ref) async => jar)],
  );
}

Future<Map<String, String>> _headers(ProviderContainer container, String url) =>
    container.read(_probeProvider(url).future);

void main() {
  group('imageHeadersForUrl', () {
    test('replays jar cookies as a Cookie header', () async {
      final jar = CookieJar();
      final uri = Uri.parse('https://novels.example/ch/1');
      await jar.saveFromResponse(uri, [
        Cookie('cf_clearance', 'abc123'),
        Cookie('__cf_bm', 'def456'),
      ]);
      final container = _containerWith(jar);
      addTearDown(container.dispose);

      final headers = await _headers(
        container,
        'https://novels.example/ch/1/img.png',
      );
      expect(headers['Cookie'], contains('cf_clearance=abc123'));
      expect(headers['Cookie'], contains('__cf_bm=def456'));
    });

    test('empty jar yields no headers', () async {
      final container = _containerWith(CookieJar());
      addTearDown(container.dispose);

      expect(
        await _headers(container, 'https://novels.example/img.png'),
        isEmpty,
      );
    });

    test('does not leak cookies across hosts', () async {
      final jar = CookieJar();
      await jar.saveFromResponse(Uri.parse('https://novels.example/'), [
        Cookie('session', 'secret'),
      ]);
      final container = _containerWith(jar);
      addTearDown(container.dispose);

      expect(await _headers(container, 'https://cdn.other/img.png'), isEmpty);
    });

    test('garbage urls yield no headers instead of throwing', () async {
      final container = _containerWith(CookieJar());
      addTearDown(container.dispose);

      expect(await _headers(container, 'not a url'), isEmpty);
      expect(await _headers(container, ''), isEmpty);
    });
  });
}
