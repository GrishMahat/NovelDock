import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../network/client.dart';
import '../utils/logger.dart';
import 'models.dart';

const _tag = 'Registry';

/// RegistryManager handles fetching registry JSON files (from URL or local),
/// parsing them, and downloading provider JS/icon files from the same repo.
class RegistryManager {
  final Dio _dio;
  final AppConfig _config;

  RegistryManager(this._dio, this._config);

  /// Fetch registry JSON from a URL.
  Future<RegistryMetadata?> fetchRegistryJson(String url) async {
    final rawUrl = _resolveRawUrl(url, path: 'registry.json');
    if (rawUrl == null) {
      Log.e(_tag, 'Invalid URL: $url');
      return null;
    }

    Log.i(_tag, 'Fetching registry JSON from: $rawUrl');
    try {
      final response = await _dio.get(
        rawUrl,
        options: Options(responseType: ResponseType.plain),
      );

      if (response.statusCode != 200) {
        Log.e(_tag, 'Registry fetch failed: HTTP ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.data as String) as Map<String, dynamic>;
      final metadata = RegistryMetadata.fromJson(json);
      Log.ok(_tag, 'Got registry "${metadata.name ?? 'unnamed'}" with ${metadata.providers.length} providers');
      return metadata;
    } on DioException catch (e) {
      Log.e(_tag, 'Dio error fetching registry: ${e.message}');
      return null;
    } catch (e) {
      Log.e(_tag, 'Error parsing registry JSON: $e');
      return null;
    }
  }

  /// Check if remote registry has a newer version than local.
  /// Returns true if remote `updated` timestamp is newer.
  Future<bool> checkForUpdates(String url, int? localUpdated) async {
    try {
      final metadata = await fetchRegistryJson(url);
      if (metadata == null || metadata.updated == null) return false;
      if (localUpdated == null) return true;
      return metadata.updated! > localUpdated;
    } catch (e) {
      Log.d(_tag, 'Update check failed: $e');
      return false;
    }
  }

  /// Sync a registry from a URL: download JSON + all provider JS and icons.
  /// Files are resolved relative to the JSON file's location in the repo.
  Future<List<ProviderMeta>> syncRegistry(String registryId, String url) async {
    Log.i(_tag, 'Syncing registry "$registryId" from $url');

    final rawUrl = _resolveRawUrl(url, path: 'registry.json');
    if (rawUrl == null) {
      Log.e(_tag, 'Invalid URL: $url');
      return [];
    }

    final metadata = await fetchRegistryJson(url);
    if (metadata == null) {
      Log.e(_tag, 'Failed to fetch metadata for $registryId');
      return [];
    }

    return await _syncMetadata(registryId, metadata, rawBaseUrl: _getBaseUrl(rawUrl));
  }

  /// Sync a registry from a local JSON file.
  /// JS/icon files are resolved relative to the JSON file's directory.
  Future<List<ProviderMeta>> syncRegistryFromFile(String registryId, String filePath) async {
    Log.i(_tag, 'Syncing registry "$registryId" from local file: $filePath');

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        Log.e(_tag, 'File not found: $filePath');
        return [];
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final metadata = RegistryMetadata.fromJson(json);

      final localDir = Directory(p.dirname(filePath)).path;
      return await _syncMetadata(registryId, metadata, localBaseDir: localDir);
    } catch (e) {
      Log.e(_tag, 'Error syncing from file: $e');
      return [];
    }
  }

  /// Internal: sync metadata — download/copy JS and icon files.
  Future<List<ProviderMeta>> _syncMetadata(
    String registryId,
    RegistryMetadata metadata, {
    String? rawBaseUrl,
    String? localBaseDir,
  }) async {
    // Registry directory — mirror the repo structure
    final registryDir = _config.registryDir(registryId);
    await registryDir.create(recursive: true);

    // Save metadata.json as-is
    final metadataFile = File(_config.registryMetadataPath(registryId));
    await metadataFile.writeAsString(jsonEncode(metadata.toJson()));
    Log.i(_tag, 'Cached registry JSON to: ${metadataFile.path}');

    final downloaded = <ProviderMeta>[];

    for (final provider in metadata.providers) {
      // Download/copy JS file using the path from metadata (relative to JSON)
      String? jsSource;
      if (rawBaseUrl != null) {
        jsSource = await _fetchString('$rawBaseUrl${provider.file}');
      } else if (localBaseDir != null) {
        jsSource = await _readLocalFile('$localBaseDir/${provider.file}');
      }

      if (jsSource != null) {
        // Save to same relative path under registry dir
        final jsPath = p.join(registryDir.path, provider.file);
        final jsFile = File(jsPath);
        await jsFile.parent.create(recursive: true);
        await jsFile.writeAsString(jsSource);
      } else {
        Log.w(_tag, 'Failed to load JS for provider ${provider.id}');
        continue;
      }

      // Download/copy icon using the path from metadata (relative to JSON)
      if (provider.icon != null) {
        if (rawBaseUrl != null) {
          final iconBytes = await _fetchBytes('$rawBaseUrl${provider.icon}');
          if (iconBytes != null) {
            final iconPath = p.join(registryDir.path, provider.icon!);
            final iconFile = File(iconPath);
            await iconFile.parent.create(recursive: true);
            await iconFile.writeAsBytes(iconBytes);
          }
        } else if (localBaseDir != null) {
          final iconPath = p.join(registryDir.path, provider.icon!);
          await _copyLocalFile('$localBaseDir/${provider.icon}', iconPath);
        }
      }

      downloaded.add(ProviderMeta(
        id: provider.id,
        name: provider.name,
        lang: provider.lang,
        baseUrl: provider.baseUrl,
        file: provider.file,
        version: provider.version,
        author: provider.author,
        icon: provider.icon,
        nsfw: provider.nsfw,
        registryId: registryId,
      ));
    }

    Log.ok(_tag, 'Synced ${downloaded.length}/${metadata.providers.length} providers');
    return downloaded;
  }

  /// Load cached registry JSON.
  Future<RegistryMetadata?> loadCachedMetadata(String registryId) async {
    final metadataPath = _config.registryMetadataPath(registryId);
    final metadataFile = File(metadataPath);
    if (!await metadataFile.exists()) {
      Log.d(_tag, 'No cached metadata for: $registryId');
      return null;
    }

    try {
      final content = await metadataFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return RegistryMetadata.fromJson(json);
    } catch (e) {
      Log.e(_tag, 'Error parsing cached metadata: $e');
      return null;
    }
  }

  /// Load cached JS source for a provider.
  /// Resolves the file path from metadata.json relative to the registry dir.
  Future<String?> loadCachedProviderJs(String providerId) async {
    // Search registries for this provider's JS file
    final registriesDir = _config.registriesDir;
    if (!await registriesDir.exists()) return null;

    await for (final entity in registriesDir.list()) {
      if (entity is! Directory) continue;
      final registryId = p.basename(entity.path);
      final metadata = await loadCachedMetadata(registryId);
      if (metadata == null) continue;

      for (final provider in metadata.providers) {
        if (provider.id == providerId) {
          final jsPath = p.join(_config.registryDir(registryId).path, provider.file);
          final jsFile = File(jsPath);
          if (await jsFile.exists()) {
            try {
              final content = await jsFile.readAsString();
              Log.ok(_tag, 'Loaded ${content.length} chars of JS for "$providerId"');
              return content;
            } catch (e) {
              Log.e(_tag, 'Error reading JS file: $e');
            }
          }
        }
      }
    }

    Log.e(_tag, 'JS file not found for provider: $providerId');
    return null;
  }

  /// Load cached icon for a provider.
  /// Resolves the icon path from metadata.json relative to the registry dir.
  File? loadCachedProviderIcon(String providerId) {
    final registriesDir = _config.registriesDir;
    if (!registriesDir.existsSync()) return null;

    for (final entity in registriesDir.listSync()) {
      if (entity is! Directory) continue;
      final registryId = p.basename(entity.path);
      final metadataDir = _config.registryDir(registryId);
      final metadataPath = _config.registryMetadataPath(registryId);
      final metadataFile = File(metadataPath);
      if (!metadataFile.existsSync()) continue;

      try {
        final json = jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
        final metadata = RegistryMetadata.fromJson(json);
        for (final provider in metadata.providers) {
          if (provider.id == providerId && provider.icon != null) {
            final iconPath = p.join(metadataDir.path, provider.icon!);
            final iconFile = File(iconPath);
            if (iconFile.existsSync()) return iconFile;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Check if a provider's JS file is cached locally.
  Future<bool> isProviderCached(String providerId) async {
    final js = await loadCachedProviderJs(providerId);
    return js != null;
  }

  // ─── URL resolution helpers ────────────────────────────────

  /// Resolve a path relative to a raw GitHub URL.
  /// Input: https://raw.githubusercontent.com/user/repo/main/registry.json
  /// Returns base URL: https://raw.githubusercontent.com/user/repo/main/
  String? _resolveRawUrl(String url, {String path = 'registry.json'}) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    if (uri.host == 'github.com') {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length >= 2) {
        final owner = segments[0];
        final repo = segments[1];
        return 'https://raw.githubusercontent.com/$owner/$repo/main/$path';
      }
    }

    if (uri.host == 'raw.githubusercontent.com') {
      // URL already points to raw content — replace filename with path
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length >= 3) {
        final base = segments.sublist(0, 3).join('/');
        return 'https://raw.githubusercontent.com/$base/$path';
      }
    }

    // Generic URL: append path
    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    // Replace filename with path if URL points to a file
    final lastSlash = base.lastIndexOf('/');
    if (lastSlash > 0) {
      return '${base.substring(0, lastSlash + 1)}$path';
    }
    return '$base/$path';
  }

  /// Extract base URL from a raw URL (everything before the filename)
  String _getBaseUrl(String rawUrl) {
    final lastSlash = rawUrl.lastIndexOf('/');
    return lastSlash > 0 ? '${rawUrl.substring(0, lastSlash + 1)}' : '$rawUrl/';
  }

  // ─── HTTP helpers ─────────────────────────────────────────

  Future<String?> _fetchString(String url) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      if (response.statusCode == 200) return response.data as String;
    } catch (e) {
      Log.w(_tag, 'Failed to fetch: $url — $e');
    }
    return null;
  }

  Future<List<int>?> _fetchBytes(String url) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.statusCode == 200) return response.data as List<int>;
    } catch (e) {
      Log.w(_tag, 'Failed to fetch bytes: $url — $e');
    }
    return null;
  }

  Future<String?> _readLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) return await file.readAsString();
    } catch (e) {
      Log.w(_tag, 'Failed to read local file: $path — $e');
    }
    return null;
  }

  Future<void> _copyLocalFile(String src, String dest) async {
    try {
      final srcFile = File(src);
      if (await srcFile.exists()) {
        await File(dest).parent.create(recursive: true);
        await srcFile.copy(dest);
      }
    } catch (e) {
      Log.w(_tag, 'Failed to copy: $src → $dest — $e');
    }
  }
}

/// Provider for RegistryManager
final registryManagerProvider = FutureProvider<RegistryManager>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  final config = await AppConfig.getInstance();
  return RegistryManager(dio, config);
});
