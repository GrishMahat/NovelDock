import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';

const _tag = 'Config';

/// Platform-aware application paths following XDG conventions.
///
/// Config directory (settings, registry metadata — small, user-editable):
///   Linux:   ~/.config/noveldock/
///   macOS:   ~/Library/Application Support/noveldock/
///   Windows: %APPDATA%/noveldock/
///   Android/iOS: `<app documents>`/noveldock/config/
///
/// Data directory (providers, database, cookies — large, machine-managed):
///   Linux:   ~/.local/share/noveldock/
///   macOS:   ~/Library/Application Support/noveldock/
///   Windows: %LOCALAPPDATA%/noveldock/
///   Android/iOS: `<app documents>`/noveldock/data/
class AppConfig {
  static AppConfig? _instance;

  /// Config directory: settings, registry metadata.json
  final Directory configDir;

  /// Data directory: provider JS files, database, cookies
  final Directory dataDir;

  AppConfig._({required this.configDir, required this.dataDir});

  /// Registry metadata storage (config — small, user-editable)
  Directory get registriesDir =>
      Directory(p.join(configDir.path, 'registries'));

  /// Provider JS files storage (data — downloaded content)
  Directory get providersDir => Directory(p.join(dataDir.path, 'providers'));

  /// Cookie storage (data)
  Directory get cookiesDir => Directory(p.join(dataDir.path, 'cookies'));

  /// Database file location (data)
  String get databasePath => p.join(dataDir.path, 'noveldock.sqlite');

  static Future<AppConfig> getInstance() async {
    if (_instance != null) return _instance!;

    Log.i(_tag, 'Initializing AppConfig...');
    final configDir = await _resolveConfigDir();
    final dataDir = await _resolveDataDir();
    Log.i(_tag, 'Config dir: ${configDir.path}');
    Log.i(_tag, 'Data dir: ${dataDir.path}');

    _instance = AppConfig._(configDir: configDir, dataDir: dataDir);

    // Ensure all subdirectories exist
    for (final dir in [
      configDir,
      dataDir,
      _instance!.registriesDir,
      _instance!.providersDir,
      _instance!.cookiesDir,
    ]) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    return _instance!;
  }

  static Future<Directory> _resolveConfigDir() async {
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return Directory(p.join(home, '.config', 'noveldock'));
      }
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return Directory(
          p.join(home, 'Library', 'Application Support', 'noveldock'),
        );
      }
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        return Directory(p.join(appData, 'noveldock'));
      }
    }
    // Android, iOS, fallback
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'noveldock', 'config'));
  }

  static Future<Directory> _resolveDataDir() async {
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null) {
        return Directory(p.join(home, '.local', 'share', 'noveldock'));
      }
    }
    if (Platform.isMacOS) {
      // macOS uses same dir for both config and data
      return await _resolveConfigDir();
    }
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null) {
        return Directory(p.join(localAppData, 'noveldock'));
      }
    }
    // Android, iOS, fallback
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'noveldock', 'data'));
  }

  // ─── Id sanitization ──────────────────────────────────

  /// Sanitizes a registry/provider id before it's used in a path.
  /// Prevents path traversal (`..`, `/`, `\`) and null bytes from
  /// escaping the intended directory, in case an id ever originates
  /// from external data (e.g. a downloaded registry's own metadata)
  /// rather than being generated internally.
  static String _sanitizeId(String id) {
    final cleaned = id.replaceAll(RegExp(r'[\/\\\x00]'), '_');
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
      throw ArgumentError.value(id, 'id', 'Invalid registry/provider id');
    }
    return cleaned;
  }

  // ─── Path helpers ─────────────────────────────────────

  /// Path to a cached registry's metadata.json
  String registryMetadataPath(String registryId) {
    return p.join(registriesDir.path, _sanitizeId(registryId), 'metadata.json');
  }

  /// Directory for a specific registry
  Directory registryDir(String registryId) {
    return Directory(p.join(registriesDir.path, _sanitizeId(registryId)));
  }

  /// Icons directory for a specific registry
  Directory registryIconsDir(String registryId) {
    return Directory(
      p.join(registriesDir.path, _sanitizeId(registryId), 'icons'),
    );
  }

  /// Path to a provider's JS file within a registry
  String registryProviderJsPath(String registryId, String providerId) {
    return p.join(
      registriesDir.path,
      _sanitizeId(registryId),
      '${_sanitizeId(providerId)}.js',
    );
  }

  /// Path to a provider's icon within a registry
  String registryProviderIconPath(String registryId, String providerId) {
    return p.join(
      registriesDir.path,
      _sanitizeId(registryId),
      'icons',
      '${_sanitizeId(providerId)}.png',
    );
  }

  // ─── Legacy paths (for backward compat) ────────────────

  /// Path to a cached provider's JS source (legacy)
  String providerJsPath(String providerId) {
    return p.join(providersDir.path, _sanitizeId(providerId), 'provider.js');
  }

  /// Path to a cached provider's icon (legacy)
  String providerIconPath(String providerId) {
    return p.join(providersDir.path, _sanitizeId(providerId), 'icon.png');
  }

  /// Path to a cached provider's local metadata (legacy)
  String providerInfoPath(String providerId) {
    return p.join(providersDir.path, _sanitizeId(providerId), 'info.json');
  }

  /// Directory for a specific provider (legacy)
  Directory providerDir(String providerId) {
    return Directory(p.join(providersDir.path, _sanitizeId(providerId)));
  }
}
