import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../network/client.dart';
import '../utils/logger.dart';
import 'models.dart';

const _tag = 'Registry';

/// RegistryManager handles fetching metadata.json from Git repos,
/// parsing it, and downloading provider JS files.
class RegistryManager {
  final Dio _dio;
  final AppConfig _config;

  RegistryManager(this._dio, this._config);

  /// Fetch metadata.json from a Git repo URL.
  Future<RegistryMetadata?> fetchMetadata(String repoUrl) async {
    final rawUrl = _toRawUrl(repoUrl);
    Log.i(_tag, 'Fetching metadata from: $rawUrl');
    if (rawUrl == null) {
      Log.e(_tag, 'Invalid repo URL: $repoUrl');
      return null;
    }

    try {
      final response = await _dio.get(
        rawUrl,
        options: Options(responseType: ResponseType.plain),
      );

      if (response.statusCode != 200) {
        Log.e(_tag, 'Metadata fetch failed: HTTP ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.data as String) as Map<String, dynamic>;
      final metadata = RegistryMetadata.fromJson(json);
      Log.ok(_tag, 'Got ${metadata.providers.length} providers from metadata');
      return metadata;
    } on DioException catch (e) {
      Log.e(_tag, 'Dio error fetching metadata: ${e.message}');
      return null;
    } catch (e) {
      Log.e(_tag, 'Error parsing metadata: $e');
      return null;
    }
  }

  /// Download a single provider JS file from its repo URL.
  Future<String?> fetchProviderJs(String repoUrl, String fileName) async {
    final rawUrl = _toRawUrl(repoUrl, path: fileName);
    Log.i(_tag, 'Fetching provider JS: $rawUrl');
    if (rawUrl == null) return null;

    try {
      final response = await _dio.get(
        rawUrl,
        options: Options(responseType: ResponseType.plain),
      );

      if (response.statusCode != 200) return null;
      Log.ok(_tag, 'Downloaded ${response.data.length} chars of JS');
      return response.data as String;
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch metadata and all provider JS files for a registry.
  Future<List<ProviderMeta>> syncRegistry(String registryId, String repoUrl) async {
    Log.i(_tag, 'Syncing registry: $registryId from $repoUrl');
    final metadata = await fetchMetadata(repoUrl);
    if (metadata == null) {
      Log.e(_tag, 'Failed to fetch metadata for $registryId');
      return [];
    }

    // Cache metadata.json
    final metadataPath = _config.registryMetadataPath(registryId);
    final metadataFile = File(metadataPath);
    await metadataFile.parent.create(recursive: true);
    await metadataFile.writeAsString(jsonEncode({
      'version': metadata.version,
      'providers': metadata.providers.map((p) => p.toJson()).toList(),
    }));
    Log.i(_tag, 'Cached metadata to: $metadataPath');

    // Download each provider's JS file
    final downloaded = <ProviderMeta>[];
    for (final provider in metadata.providers) {
      if (provider.repo == null) continue;

      final jsSource = await fetchProviderJs(provider.repo!, provider.file);
      if (jsSource == null) continue;

      // Save JS file
      final providerDir = _config.providerDir(provider.id);
      await providerDir.create(recursive: true);

      final jsFile = File(_config.providerJsPath(provider.id));
      await jsFile.writeAsString(jsSource);

      // Save local metadata copy
      final infoFile = File(_config.providerInfoPath(provider.id));
      await infoFile.writeAsString(jsonEncode(provider.toJson()));

      downloaded.add(provider);
    }

    Log.ok(_tag, 'Synced ${downloaded.length}/${metadata.providers.length} providers');
    return downloaded;
  }

  /// Load cached metadata for a registry.
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
  Future<String?> loadCachedProviderJs(String providerId) async {
    final jsPath = _config.providerJsPath(providerId);
    Log.i(_tag, 'Loading cached JS for "$providerId" from: $jsPath');
    final jsFile = File(jsPath);
    if (!await jsFile.exists()) {
      Log.e(_tag, 'JS file not found: $jsPath');
      return null;
    }

    try {
      final content = await jsFile.readAsString();
      Log.ok(_tag, 'Loaded ${content.length} chars of JS for "$providerId"');
      return content;
    } catch (e) {
      Log.e(_tag, 'Error reading JS file: $e');
      return null;
    }
  }

  /// Check if a provider's JS file is cached locally.
  Future<bool> isProviderCached(String providerId) async {
    final jsFile = File(_config.providerJsPath(providerId));
    return await jsFile.exists();
  }

  /// Convert a GitHub repo URL to a raw content base URL.
  String? _toRawUrl(String repoUrl, {String path = 'metadata.json'}) {
    final uri = Uri.tryParse(repoUrl);
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
      return '$repoUrl/$path';
    }

    final base = repoUrl.endsWith('/') ? repoUrl.substring(0, repoUrl.length - 1) : repoUrl;
    return '$base/main/$path';
  }
}

/// Provider for RegistryManager
final registryManagerProvider = FutureProvider<RegistryManager>((ref) async {
  final dio = await ref.watch(dioProvider.future);
  final config = await AppConfig.getInstance();
  return RegistryManager(dio, config);
});
