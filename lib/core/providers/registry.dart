import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../config/app_config.dart';
import '../network/client.dart';
import '../utils/logger.dart';
import 'models.dart';

part 'registry.g.dart';

const _tag = 'Registry';

/// RegistryManager handles fetching registry JSON files (from URL or local),
/// parsing them, and downloading provider JS/icon files from the same repo.
class RegistryManager {
  final Dio _dio;
  final AppConfig _config;

  RegistryManager(this._dio, this._config);

  /// Directory where this registry's cached files live.
  Directory registryDir(String registryId) => _config.registryDir(registryId);

  /// Hex sha256 of exact bytes. Recorded at sync time, verified on load.
  static String sha256Hex(String content) =>
      sha256.convert(utf8.encode(content)).toString();

  /// Resolve a user-supplied registry URL to its canonical registry.json
  /// URL (github.com -> raw.githubusercontent.com, etc.). Used for
  /// duplicate detection: two URL spellings of the same repo must not
  /// become two registry entries.
  static String? resolveRawUrl(String url) =>
      _resolveRawUrlStatic(url, path: 'registry.json');

  /// Remote fetches are https-only. The sole exception is http loopback for
  /// local registry development. Everything else (notably http:// hosts on
  /// hostile networks serving executable JS) is rejected before any bytes
  /// move.
  static bool isAllowedRemoteUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  /// Validate a registry-controlled relative path (provider `file`/`icon`).
  /// Rejects traversal (..), absolute paths, drive letters, backslashes and
  /// empties so a malicious registry.json cannot escape the registry dir on
  /// write, or read outside the source dir for local registries. Returns the
  /// normalized relative path, or null when unsafe.
  static String? safeRelativePath(String raw) {
    if (raw.isEmpty) return null;
    final normalized = p.normalize(raw.replaceAll('\\', '/'));
    if (normalized.isEmpty || normalized == '.') return null;
    if (normalized.startsWith('/') || p.isAbsolute(normalized)) return null;
    if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return null;
    final segments = p.split(normalized);
    if (segments.any((s) => s == '..' || s.isEmpty)) return null;
    return normalized;
  }

  /// Fetch registry JSON from a URL. Returns null on failure (error logged).
  Future<RegistryMetadata?> fetchRegistryJson(String url) async {
    final rawUrl = _resolveRawUrlStatic(url, path: 'registry.json');
    if (rawUrl == null) {
      Log.e(_tag, 'Invalid URL: $url');
      return null;
    }
    if (!isAllowedRemoteUrl(rawUrl)) {
      Log.e(_tag, 'Refused non-https registry URL: $url');
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
      Log.ok(
        _tag,
        'Got registry "${metadata.name ?? 'unnamed'}" with ${metadata.providers.length} providers',
      );
      return metadata;
    } on DioException catch (e) {
      Log.e(_tag, 'Dio error fetching registry: ${e.message}');
      return null;
    } catch (e) {
      Log.e(_tag, 'Error parsing registry JSON: $e');
      return null;
    }
  }

  /// Fetch registry JSON from a URL. Returns error string on failure, null on success.
  Future<String?> fetchRegistryJsonWithError(String url) async {
    final rawUrl = Uri.tryParse(url);
    if (rawUrl == null || !rawUrl.hasScheme) {
      return 'Invalid URL format';
    }

    final resolvedUrl = _resolveRawUrlStatic(url, path: 'registry.json');
    if (resolvedUrl == null) {
      return 'Could not resolve registry URL: $url';
    }
    if (!isAllowedRemoteUrl(resolvedUrl)) {
      return 'Only https:// registry URLs are allowed (http loopback '
          'excepted for local development).';
    }

    Log.i(_tag, 'Fetching registry JSON from: $resolvedUrl');
    try {
      final response = await _dio.get(
        resolvedUrl,
        options: Options(responseType: ResponseType.plain),
      );

      if (response.statusCode == 404) {
        return 'Registry not found (404) at $resolvedUrl.\nMake sure the repo contains a registry.json file.';
      }
      if (response.statusCode != 200) {
        return 'Registry fetch failed: HTTP ${response.statusCode}';
      }

      final json = jsonDecode(response.data as String) as Map<String, dynamic>;
      final metadata = RegistryMetadata.fromJson(json);
      Log.ok(
        _tag,
        'Got registry "${metadata.name ?? 'unnamed'}" with ${metadata.providers.length} providers',
      );
      return null;
    } on DioException catch (e) {
      final msg = e.message ?? 'Unknown network error';
      final statusCode = e.response?.statusCode;
      if (statusCode == 404) {
        return 'Registry not found (404) at $resolvedUrl.\nMake sure the repo contains a registry.json file.';
      }
      return 'Network error: $msg';
    } catch (e) {
      return 'Error parsing registry JSON: $e';
    }
  }

  /// Check if remote registry has newer content than the local cache.
  /// Returns true if the remote `updated` timestamp is newer, or if the
  /// provider list differs from the cached metadata (version/file/baseUrl
  /// changes are detected even when the `updated` timestamp was not bumped).
  Future<bool> checkForUpdates(String url, {RegistryMetadata? local}) async {
    try {
      final metadata = await fetchRegistryJson(url);
      if (metadata == null) return false;

      if (local == null) return true;

      // Timestamp check: remote explicitly newer.
      if (metadata.updated != null &&
          local.updated != null &&
          metadata.updated! > local.updated!) {
        return true;
      }

      // Content check: provider list/versions differ from cache.
      final remoteProviders = metadata.providers;
      final localProviders = local.providers;
      if (remoteProviders.length != localProviders.length) return true;

      for (final rp in remoteProviders) {
        ProviderMeta? lp;
        for (final p in localProviders) {
          if (p.id == rp.id) {
            lp = p;
            break;
          }
        }
        if (lp == null) return true;
        if (lp.version != rp.version) return true;
        if (lp.file != rp.file) return true;
        if (lp.baseUrl != rp.baseUrl) return true;
      }
      return false;
    } catch (e) {
      Log.d(_tag, 'Update check failed: $e');
      return false;
    }
  }

  /// Sync a registry from a URL: download JSON + all provider JS and icons.
  /// Files are resolved relative to the JSON file's location in the repo.
  Future<List<ProviderMeta>> syncRegistry(String registryId, String url) async {
    Log.i(_tag, 'Syncing registry "$registryId" from $url');

    final rawUrl = _resolveRawUrlStatic(url, path: 'registry.json');
    if (rawUrl == null) {
      Log.e(_tag, 'Invalid URL: $url');
      return [];
    }
    if (!isAllowedRemoteUrl(rawUrl)) {
      Log.e(_tag, 'Refused non-https registry URL: $url');
      return [];
    }

    final metadata = await fetchRegistryJson(url);
    if (metadata == null) {
      Log.e(_tag, 'Failed to fetch metadata for $registryId');
      return [];
    }

    return await _syncMetadata(
      registryId,
      metadata,
      rawBaseUrl: _getBaseUrl(rawUrl),
    );
  }

  /// Sync a registry from a local JSON file.
  /// JS/icon files are resolved relative to the JSON file's directory.
  Future<List<ProviderMeta>> syncRegistryFromFile(
    String registryId,
    String filePath,
  ) async {
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

  /// Internal: sync metadata — download/copy JS and icon files in parallel.
  Future<List<ProviderMeta>> _syncMetadata(
    String registryId,
    RegistryMetadata metadata, {
    String? rawBaseUrl,
    String? localBaseDir,
  }) async {
    final registryDir = _config.registryDir(registryId);
    await registryDir.create(recursive: true);

    final results = await Future.wait(
      metadata.providers.map((provider) async {
        // Registry-controlled paths stay inside the registry dir. A `..`,
        // absolute path, or drive letter here is an escape attempt, not a
        // typo: fail the provider instead of writing outside its sandbox.
        final safeFile = safeRelativePath(provider.file);
        if (safeFile == null) {
          Log.e(
            _tag,
            'Rejected unsafe provider file path "${provider.file}" '
            'for provider ${provider.id}',
          );
          return null;
        }
        final safeIcon = provider.icon == null
            ? null
            : safeRelativePath(provider.icon!);
        if (provider.icon != null && safeIcon == null) {
          Log.e(
            _tag,
            'Rejected unsafe provider icon path "${provider.icon}" '
            'for provider ${provider.id}',
          );
          return null;
        }

        final futures = <Future<dynamic>>[];
        final jsFuture = rawBaseUrl != null
            ? _fetchString('$rawBaseUrl$safeFile')
            : _readLocalFile('$localBaseDir/$safeFile');
        futures.add(jsFuture);

        Future<List<int>?>? iconFuture;
        if (safeIcon != null && rawBaseUrl != null) {
          iconFuture = _fetchBytes('$rawBaseUrl$safeIcon');
          futures.add(iconFuture);
        }

        final completed = await Future.wait(futures);
        final jsSource = completed[0] as String?;

        if (jsSource == null) {
          Log.w(_tag, 'Failed to load JS for provider ${provider.id}');
          return null;
        }

        List<int>? iconBytes;
        if (iconFuture != null && completed.length > 1) {
          iconBytes = completed[1] as List<int>?;
        }

        final jsPath = p.join(registryDir.path, safeFile);
        final jsFile = File(jsPath);
        await jsFile.parent.create(recursive: true);
        await jsFile.writeAsString(jsSource);

        if (iconBytes != null) {
          final iconPath = p.join(registryDir.path, safeIcon!);
          final iconFile = File(iconPath);
          await iconFile.parent.create(recursive: true);
          await iconFile.writeAsBytes(iconBytes);
        } else if (safeIcon != null && localBaseDir != null) {
          final iconPath = p.join(registryDir.path, safeIcon);
          await _copyLocalFile('$localBaseDir/$safeIcon', iconPath);
        }

        return ProviderMeta(
          id: provider.id,
          name: provider.name,
          lang: provider.lang,
          baseUrl: provider.baseUrl,
          // Stored verbatim so update detection (version/file/baseUrl
          // comparison against the next remote fetch) sees no phantom diff;
          // every filesystem use goes through the validated safeFile/safeIcon
          // above, and reads re-validate (see loadCachedProviderJs).
          file: provider.file,
          version: provider.version,
          author: provider.author,
          icon: provider.icon,
          nsfw: provider.nsfw,
          registryId: registryId,
          // Pin the exact bytes cached: verified on every load so
          // post-sync modification is detected instead of executed.
          sha256: sha256Hex(jsSource),
        );
      }),
    );

    final downloaded = results.whereType<ProviderMeta>().toList();

    // Only commit the new metadata once ALL provider files were written.
    // Writing it first would make the UI show the new version while the
    // runtime still loads the old JS files (stale cache inconsistency).
    if (downloaded.length != metadata.providers.length) {
      Log.w(
        _tag,
        'Sync incomplete (${downloaded.length}/${metadata.providers.length}), '
        'keeping previous metadata.json',
      );
      return downloaded;
    }

    // Commit the pinned list (with registryId + sha256), not the raw server
    // metadata: the cache must describe exactly what is on disk.
    final committed = RegistryMetadata(
      version: metadata.version,
      name: metadata.name,
      description: metadata.description,
      status: metadata.status,
      updated: metadata.updated,
      providers: downloaded,
    );
    final metadataFile = File(_config.registryMetadataPath(registryId));
    await metadataFile.writeAsString(jsonEncode(committed.toJson()));
    Log.i(_tag, 'Cached registry JSON to: ${metadataFile.path}');

    Log.ok(
      _tag,
      'Synced ${downloaded.length}/${metadata.providers.length} providers',
    );
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
  ///
  /// When several enabled registries ship the same provider id,
  /// [preferRegistryOrder] (the user's registry order, incumbent first)
  /// decides deterministically instead of filesystem mtimes: a later-added
  /// registry can never silently shadow an earlier one. Without it, falls
  /// back to most-recently-synced-wins.
  ///
  /// Content is verified against the sha256 pinned at sync time; a modified
  /// file is skipped (falling through to the next match) instead of
  /// executed. Caches synced before hashes existed load once with a warning.
  Future<String?> loadCachedProviderJs(
    String providerId, {
    List<String>? preferRegistryOrder,
  }) async {
    // Search registries for this provider's JS file
    final registriesDir = _config.registriesDir;
    if (!await registriesDir.exists()) return null;

    final matches = <(String, String, DateTime)>[];

    await for (final entity in registriesDir.list()) {
      if (entity is! Directory) continue;
      final registryId = p.basename(entity.path);
      final metadata = await loadCachedMetadata(registryId);
      if (metadata == null) continue;

      for (final provider in metadata.providers) {
        if (provider.id == providerId) {
          // Cached metadata predates path validation: re-validate on read.
          final safeFile = safeRelativePath(provider.file);
          if (safeFile == null) {
            Log.e(
              _tag,
              'Skipping unsafe cached path "${provider.file}" for '
              '"$providerId" in registry "$registryId"',
            );
            continue;
          }
          final jsPath = p.join(_config.registryDir(registryId).path, safeFile);
          final jsFile = File(jsPath);
          if (await jsFile.exists()) {
            final metadataFile = File(_config.registryMetadataPath(registryId));
            final metadataModified = await metadataFile.lastModified();
            matches.add((jsPath, registryId, metadataModified));
          }
        }
      }
    }

    if (matches.isEmpty) {
      Log.e(_tag, 'JS file not found for provider: $providerId');
      return null;
    }

    matches.sort((a, b) {
      if (preferRegistryOrder != null) {
        final ai = preferRegistryOrder.indexOf(a.$2);
        final bi = preferRegistryOrder.indexOf(b.$2);
        final ao = ai < 0 ? preferRegistryOrder.length : ai;
        final bo = bi < 0 ? preferRegistryOrder.length : bi;
        if (ao != bo) return ao.compareTo(bo);
      }
      return b.$3.compareTo(a.$3);
    });

    for (final (jsPath, registryId, _) in matches) {
      String content;
      try {
        content = await File(jsPath).readAsString();
      } catch (e) {
        Log.e(_tag, 'Error reading JS file: $e');
        continue;
      }
      final expected = await _expectedProviderSha(registryId, providerId);
      if (expected == null) {
        Log.w(
          _tag,
          'No recorded hash for "$providerId" (legacy cache); loading '
          'unverified. Re-sync the registry to pin it.',
        );
        return content;
      }
      if (sha256Hex(content) != expected) {
        Log.e(
          _tag,
          'Integrity mismatch for "$providerId" from registry '
          '"$registryId": file changed since sync, skipping',
        );
        continue;
      }
      Log.ok(
        _tag,
        'Loaded ${content.length} chars of JS for "$providerId" '
        '(from registry "$registryId", hash verified)',
      );
      return content;
    }

    Log.e(_tag, 'No verified JS for provider: $providerId');
    return null;
  }

  /// Recorded sha256 for a provider in one registry's committed metadata.
  /// Null when the cache predates hash pinning (or the entry is unknown).
  Future<String?> _expectedProviderSha(
    String registryId,
    String providerId,
  ) async {
    final metadata = await loadCachedMetadata(registryId);
    if (metadata == null) return null;
    for (final provider in metadata.providers) {
      if (provider.id == providerId) return provider.sha256;
    }
    return null;
  }

  /// Load cached icon for a provider.
  /// Resolves the icon path from metadata.json relative to the registry dir.
  /// [preferRegistryOrder] applies the same incumbent-wins rule as JS
  /// resolution so icon and code come from the same registry.
  File? loadCachedProviderIcon(
    String providerId, {
    List<String>? preferRegistryOrder,
  }) {
    final registriesDir = _config.registriesDir;
    if (!registriesDir.existsSync()) return null;

    final dirs = registriesDir.listSync().whereType<Directory>().toList();
    if (preferRegistryOrder != null) {
      dirs.sort((a, b) {
        final ai = preferRegistryOrder.indexOf(p.basename(a.path));
        final bi = preferRegistryOrder.indexOf(p.basename(b.path));
        final ao = ai < 0 ? preferRegistryOrder.length : ai;
        final bo = bi < 0 ? preferRegistryOrder.length : bi;
        return ao.compareTo(bo);
      });
    }

    for (final entity in dirs) {
      final registryId = p.basename(entity.path);
      final metadataDir = _config.registryDir(registryId);
      final metadataPath = _config.registryMetadataPath(registryId);
      final metadataFile = File(metadataPath);
      if (!metadataFile.existsSync()) continue;

      try {
        final json =
            jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
        final metadata = RegistryMetadata.fromJson(json);
        for (final provider in metadata.providers) {
          if (provider.id == providerId && provider.icon != null) {
            final safeIcon = safeRelativePath(provider.icon!);
            if (safeIcon == null) continue;
            final iconPath = p.join(metadataDir.path, safeIcon);
            final iconFile = File(iconPath);
            if (iconFile.existsSync()) return iconFile;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Check if a provider's JS file is cached locally.
  Future<bool> isProviderCached(
    String providerId, {
    List<String>? preferRegistryOrder,
  }) async {
    final js = await loadCachedProviderJs(
      providerId,
      preferRegistryOrder: preferRegistryOrder,
    );
    return js != null;
  }

  // ─── URL resolution helpers ────────────────────────────────

  /// Resolve a path relative to a raw GitHub URL.
  /// Input: https://raw.githubusercontent.com/user/repo/main/registry.json
  /// Returns base URL: https://raw.githubusercontent.com/user/repo/main/
  static String? _resolveRawUrlStatic(
    String url, {
    String path = 'registry.json',
  }) {
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
    return lastSlash > 0 ? rawUrl.substring(0, lastSlash + 1) : '$rawUrl/';
  }

  // ─── HTTP helpers ─────────────────────────────────────────

  Future<String?> _fetchString(String url) async {
    if (!isAllowedRemoteUrl(url)) {
      Log.w(_tag, 'Refused non-https fetch: $url');
      return null;
    }
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
    if (!isAllowedRemoteUrl(url)) {
      Log.w(_tag, 'Refused non-https fetch: $url');
      return null;
    }
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
@Riverpod(keepAlive: true)
Future<RegistryManager> registryManager(Ref ref) async {
  final dio = await ref.watch(dioProvider.future);
  final config = await AppConfig.getInstance();
  return RegistryManager(dio, config);
}
