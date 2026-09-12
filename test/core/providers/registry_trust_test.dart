import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/providers/models.dart';
import 'package:noveldock/core/providers/registries.dart';
import 'package:noveldock/core/providers/registry.dart';

// Pins the extension-trust guardrails: URL canonicalization (duplicate
// detection), https-only fetching, registry-relative path validation,
// content hashing, sha round-trip, and incumbent-wins ordering. All are
// pure functions, so they are tested without instances or platform
// channels.
void main() {
  group('resolveRawUrl', () {
    test('github.com repo URL resolves to raw main registry.json', () {
      expect(
        RegistryManager.resolveRawUrl('https://github.com/u/r'),
        'https://raw.githubusercontent.com/u/r/main/registry.json',
      );
    });

    test('raw URL with blob path resolves to its own base', () {
      expect(
        RegistryManager.resolveRawUrl(
          'https://raw.githubusercontent.com/u/r/main/registry.json',
        ),
        'https://raw.githubusercontent.com/u/r/main/registry.json',
      );
    });

    test('same repo via both spellings canonicalizes identically', () {
      expect(
        RegistryManager.resolveRawUrl('https://github.com/u/r'),
        RegistryManager.resolveRawUrl(
          'https://raw.githubusercontent.com/u/r/main/registry.json',
        ),
      );
    });

    test('generic URL replaces trailing file segment', () {
      expect(
        RegistryManager.resolveRawUrl('https://example.com/a/index.html'),
        'https://example.com/a/registry.json',
      );
    });

    test('garbage returns null', () {
      expect(RegistryManager.resolveRawUrl('::::'), isNull);
    });
  });

  group('isAllowedRemoteUrl', () {
    test('https allowed', () {
      expect(
        RegistryManager.isAllowedRemoteUrl('https://example.com/r.json'),
        isTrue,
      );
    });

    test('plain http rejected', () {
      expect(
        RegistryManager.isAllowedRemoteUrl('http://example.com/r.json'),
        isFalse,
      );
    });

    test('http loopback allowed for local development', () {
      expect(
        RegistryManager.isAllowedRemoteUrl('http://localhost:8080/r.json'),
        isTrue,
      );
      expect(
        RegistryManager.isAllowedRemoteUrl('http://127.0.0.1/r.json'),
        isTrue,
      );
    });

    test('non-http schemes and schemeless rejected', () {
      expect(
        RegistryManager.isAllowedRemoteUrl('ftp://example.com/r.json'),
        isFalse,
      );
      expect(RegistryManager.isAllowedRemoteUrl('example.com/r.json'), isFalse);
      expect(RegistryManager.isAllowedRemoteUrl(''), isFalse);
    });
  });

  group('safeRelativePath', () {
    test('plain relative paths pass through', () {
      expect(
        RegistryManager.safeRelativePath('providers/royalroad.js'),
        'providers/royalroad.js',
      );
      expect(RegistryManager.safeRelativePath('icon.png'), 'icon.png');
    });

    test('traversal, absolute, drive, empty rejected', () {
      expect(RegistryManager.safeRelativePath('../../evil.js'), isNull);
      expect(RegistryManager.safeRelativePath('a/../../evil.js'), isNull);
      expect(RegistryManager.safeRelativePath('/abs/path.js'), isNull);
      expect(RegistryManager.safeRelativePath(r'C:\evil.js'), isNull);
      expect(RegistryManager.safeRelativePath(''), isNull);
      expect(RegistryManager.safeRelativePath('..'), isNull);
    });

    test('redundant separators normalize without escaping', () {
      expect(
        RegistryManager.safeRelativePath('providers//x.js'),
        'providers/x.js',
      );
    });
  });

  group('sha256Hex', () {
    test('matches the known empty-string and abc vectors', () {
      expect(
        RegistryManager.sha256Hex(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      expect(
        RegistryManager.sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('ProviderMeta sha256', () {
    test('survives a JSON round-trip', () {
      const meta = ProviderMeta(
        id: 'royalroad',
        name: 'Royal Road',
        lang: 'en',
        baseUrl: 'https://example.com',
        file: 'providers/royalroad.js',
        version: '1.0.0',
        registryId: 'default',
        sha256: 'deadbeef',
      );
      final restored = ProviderMeta.fromJson(meta.toJson());
      expect(restored.sha256, 'deadbeef');
      expect(restored.registryId, 'default');
    });

    test('absent in legacy JSON', () {
      final restored = ProviderMeta.fromJson({
        'id': 'x',
        'name': 'x',
        'lang': 'en',
        'baseUrl': 'https://example.com',
        'file': 'x.js',
        'version': '1',
      });
      expect(restored.sha256, isNull);
    });
  });

  group('enabledRegistryOrder', () {
    test('enabled ids in list order, disabled skipped', () {
      const registries = [
        RegistryInfo(id: 'a', url: 'https://a', enabled: true),
        RegistryInfo(id: 'b', url: 'https://b', enabled: false),
        RegistryInfo(id: 'c', url: 'https://c', enabled: true),
      ];
      expect(enabledRegistryOrder(registries), ['a', 'c']);
    });
  });
}
