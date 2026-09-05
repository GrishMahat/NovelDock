import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers/engine.dart';
import '../../../core/providers/models.dart';
import '../../../core/providers/registry.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/utils/logger.dart';

part 'provider_management_providers.g.dart';

const _tag = 'Providers';

/// List of registries the user has added — persisted to settings DB.
@Riverpod(keepAlive: true)
class RegistriesNotifier extends _$RegistriesNotifier {
  @override
  Future<List<RegistryInfo>> build() async {
    return await _loadFromDb();
  }

  Future<List<RegistryInfo>> _loadFromDb() async {
    try {
      final settingsDao = ref.read(settingsDaoProvider);
      final value = await settingsDao.getSetting('registries');
      if (value != null && value.isNotEmpty) {
        final list = (jsonDecode(value) as List)
            .map((e) => RegistryInfo.fromJson(e as Map<String, dynamic>))
            .toList();

        // Validate: remove registries whose metadata file is missing
        final config = await AppConfig.getInstance();
        final valid = <RegistryInfo>[];
        for (final registry in list) {
          final metadataPath = config.registryMetadataPath(registry.id);
          if (await File(metadataPath).exists()) {
            valid.add(registry);
          } else {
            Log.w(
              _tag,
              'Removing stale registry: ${registry.id} (metadata missing)',
            );
          }
        }

        if (valid.length != list.length) {
          // Save cleaned list back to DB
          final cleaned = valid.map((r) => r.toJson()).toList();
          await settingsDao.setSetting('registries', jsonEncode(cleaned));
        }

        Log.i(_tag, 'Loaded ${valid.length} registries from DB');
        return valid;
      }
    } catch (e) {
      Log.e(_tag, 'Failed to load registries from DB', e);
    }
    return [];
  }

  Future<void> _saveToDb() async {
    try {
      final settingsDao = ref.read(settingsDaoProvider);
      final json = state.value?.map((r) => r.toJson()).toList() ?? [];
      await settingsDao.setSetting('registries', jsonEncode(json));
      Log.d(_tag, 'Saved ${state.value?.length ?? 0} registries to DB');
    } catch (e) {
      Log.e(_tag, 'Failed to save registries to DB', e);
    }
  }

  void add(RegistryInfo registry) {
    final current = state.value ?? [];
    state = AsyncData([...current, registry]);
    _saveToDb();
  }

  void remove(String registryId) {
    final current = state.value ?? [];
    state = AsyncData(current.where((r) => r.id != registryId).toList());
    _saveToDb();
  }

  void updateRegistry(String registryId, RegistryInfo updated) {
    final current = state.value ?? [];
    state = AsyncData([
      for (final r in current)
        if (r.id == registryId) updated else r,
    ]);
    _saveToDb();
  }

  Future<void> toggleRegistry(String registryId) async {
    final current = state.value ?? [];
    state = AsyncData([
      for (final r in current)
        if (r.id == registryId) r.copyWith(enabled: !r.enabled) else r,
    ]);
    await _saveToDb();
    // The provider list is built from enabled registries only.
    ref.invalidate(availableProvidersProvider);
    Log.i(_tag, 'Toggled registry: $registryId');
  }
}

/// All available providers — from enabled registries only.
@Riverpod(keepAlive: true)
Future<List<ProviderMeta>> availableProviders(Ref ref) async {
  final registriesAsync = ref.watch(registriesProvider);
  final registries = registriesAsync.value ?? [];
  final registryManager = await ref.watch(registryManagerProvider.future);

  // Only load from enabled registries
  final enabledRegistries = registries.where((r) => r.enabled).toList();
  Log.i(
    _tag,
    'Loading providers from ${enabledRegistries.length}/${registries.length} enabled registries...',
  );

  // Local file registries are the source of truth: always re-sync on
  // startup so JS edits take effect without a manual sync.
  for (final registry in enabledRegistries) {
    if (!_isLocalRegistryUrl(registry.url)) continue;
    try {
      final sourceFile = File(registry.url);
      if (!await sourceFile.exists()) continue;
      Log.i(_tag, 'Re-syncing local registry "${registry.id}"...');
      await registryManager.syncRegistryFromFile(registry.id, registry.url);
    } catch (e) {
      Log.w(_tag, 'Auto re-sync failed for ${registry.id}: $e');
    }
  }

  final allProviders = <ProviderMeta>[];

  for (final registry in enabledRegistries) {
    final metadata = await registryManager.loadCachedMetadata(registry.id);
    if (metadata != null) {
      Log.i(
        _tag,
        'Got ${metadata.providers.length} providers from registry "${registry.id}"',
      );
      for (final provider in metadata.providers) {
        allProviders.add(
          ProviderMeta(
            id: provider.id,
            name: provider.name,
            lang: provider.lang,
            baseUrl: provider.baseUrl,
            file: provider.file,
            version: provider.version,
            author: provider.author,
            icon: provider.icon,
            nsfw: provider.nsfw,
            registryId: registry.id,
          ),
        );
      }
    }
  }

  Log.ok(_tag, 'Total providers found: ${allProviders.length}');

  return allProviders;
}

/// Set of enabled provider IDs — persisted to settings table.
@Riverpod(keepAlive: true)
class EnabledProvidersNotifier extends _$EnabledProvidersNotifier {
  final Completer<void> _ready = Completer<void>();

  /// Completes once the initial DB load has finished (or failed). Callers
  /// that must not act on the transient empty default state should await
  /// this — otherwise a search started at cold start would see no enabled
  /// providers and silently return nothing.
  Future<void> get ready => _ready.future;

  @override
  Set<String> build() {
    _loadFromDb();
    return const {};
  }

  Future<void> _loadFromDb() async {
    try {
      final settingsDao = ref.read(settingsDaoProvider);
      final value = await settingsDao.getSetting('enabled_providers');
      if (value != null && value.isNotEmpty) {
        final list = (jsonDecode(value) as List).cast<String>();
        state = Set<String>.from(list);
        Log.i(_tag, 'Loaded ${state.length} enabled providers from DB: $state');
      } else {
        Log.d(_tag, 'No enabled providers in DB');
      }
    } catch (e) {
      Log.e(_tag, 'Failed to load enabled providers from DB', e);
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  Future<void> _saveToDb() async {
    try {
      final settingsDao = ref.read(settingsDaoProvider);
      await settingsDao.setSetting(
        'enabled_providers',
        jsonEncode(state.toList()),
      );
      Log.d(_tag, 'Saved ${state.length} enabled providers to DB');
    } catch (e) {
      Log.e(_tag, 'Failed to save enabled providers to DB', e);
    }
  }

  void toggle(String providerId) {
    final newSet = Set<String>.from(state);
    if (newSet.contains(providerId)) {
      newSet.remove(providerId);
      Log.i(_tag, 'Disabled provider: $providerId');
    } else {
      newSet.add(providerId);
      Log.i(_tag, 'Enabled provider: $providerId');
    }
    state = newSet;
    _saveToDb();
  }

  void setEnabled(String providerId, bool enabled) {
    final newSet = Set<String>.from(state);
    if (enabled) {
      newSet.add(providerId);
    } else {
      newSet.remove(providerId);
    }
    state = newSet;
    _saveToDb();
  }
}

/// Add a new registry from a URL: fetch JSON, sync providers, add to list.
/// Returns null on success, or an error message string on failure.
///
/// Takes a [ProviderContainer] instead of a [WidgetRef] so the network work
/// survives the originating page being disposed mid-flight.
Future<String?> addRegistry(String url, ProviderContainer ref) async {
  final registryManager = await ref.read(registryManagerProvider.future);

  final id = Uri.parse(url).pathSegments.where((s) => s.isNotEmpty).join('-');

  // Two different URLs can normalize to the same id (and re-adding the same
  // URL would produce a duplicate list entry that all id-based operations
  // would then hit twice).
  final existing = ref.read(registriesProvider).value ?? const [];
  if (existing.any((r) => r.id == id || r.url == url)) {
    return 'Registry already added';
  }

  Log.i(_tag, 'Adding registry from URL: $url (id: $id)');
  final error = await registryManager.fetchRegistryJsonWithError(url);
  if (error != null) {
    Log.e(_tag, 'Failed to fetch registry from $url: $error');
    return error;
  }

  final metadata = await registryManager.fetchRegistryJson(url);
  if (metadata == null) {
    return 'Failed to parse registry metadata';
  }

  await registryManager.syncRegistry(id, url);

  final registry = RegistryInfo(
    id: id,
    url: url,
    name: metadata.name ?? id,
    description: metadata.description,
    status: metadata.status,
    enabled: true,
    lastFetchedAt: DateTime.now().millisecondsSinceEpoch,
    lastUpdated: metadata.updated,
  );

  ref.read(registriesProvider.notifier).add(registry);
  Log.ok(_tag, 'Registry added: $id');
  return null;
}

/// Add a new registry from a local JSON file.
/// Returns null on success, or an error message string on failure.
Future<String?> addRegistryFromFile(
  String filePath,
  ProviderContainer ref,
) async {
  final registryManager = await ref.read(registryManagerProvider.future);

  final filename = p.basenameWithoutExtension(filePath);
  final id =
      'local_${filename.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  Log.i(_tag, 'Adding registry from file: $filePath (id: $id)');

  final file = File(filePath);
  if (!await file.exists()) {
    return 'File not found: $filePath';
  }

  String content;
  try {
    content = await file.readAsString();
  } catch (e) {
    return 'Failed to read file: $e';
  }

  Map<String, dynamic> json;
  try {
    json = jsonDecode(content) as Map<String, dynamic>;
  } catch (e) {
    return 'Invalid JSON in file: $e';
  }

  final metadata = RegistryMetadata.fromJson(json);
  if (metadata.providers.isEmpty) {
    return 'Registry file contains no providers';
  }

  await registryManager.syncRegistryFromFile(id, filePath);

  final registry = RegistryInfo(
    id: id,
    url: filePath,
    name: metadata.name ?? filename,
    description: metadata.description,
    status: metadata.status,
    enabled: true,
    lastFetchedAt: DateTime.now().millisecondsSinceEpoch,
    lastUpdated: metadata.updated,
  );

  ref.read(registriesProvider.notifier).add(registry);
  Log.ok(_tag, 'Registry added from file: $id');
  return null;
}

bool _isLocalRegistryUrl(String url) =>
    url.startsWith('/') || url.startsWith('file://');

/// Check a single registry for updates and apply them if available.
/// Returns true if it was updated, false if already up to date or failed.
Future<bool> updateRegistryNow(String registryId, ProviderContainer ref) async {
  final registryManager = await ref.read(registryManagerProvider.future);
  final registries = ref.read(registriesProvider).value ?? [];
  final registry = registries.firstWhere(
    (r) => r.id == registryId,
    orElse: () => throw Exception('Registry not found: $registryId'),
  );

  final localMetadata = await registryManager.loadCachedMetadata(registryId);
  final hasUpdate = await registryManager.checkForUpdates(
    registry.url,
    local: localMetadata,
  );
  if (!hasUpdate) return false;

  Log.i(_tag, 'Applying update for registry: $registryId');
  final metadata = await registryManager.fetchRegistryJson(registry.url);
  if (metadata == null) return false;

  await registryManager.syncRegistry(registryId, registry.url);

  ref
      .read(registriesProvider.notifier)
      .updateRegistry(
        registryId,
        registry.copyWith(
          pendingUpdate: false,
          lastFetchedAt: DateTime.now().millisecondsSinceEpoch,
          lastUpdated: metadata.updated,
          name: metadata.name ?? registry.name,
        ),
      );

  // Force provider list to refresh...
  ref.invalidate(availableProvidersProvider);
  // ...and drop any loaded JS instance so search/browse immediately use the
  // newly synced provider code instead of the previous runtime.
  ref.invalidate(providerInstanceProvider);

  Log.ok(_tag, 'Registry updated: $registryId');
  return true;
}

/// Manually check all URL-based registries for updates and apply them.
/// Returns the number of registries that were updated.
Future<int> updateAllRegistries(ProviderContainer ref) async {
  final registryManager = await ref.read(registryManagerProvider.future);
  final registries = ref.read(registriesProvider).value ?? [];

  var updatedCount = 0;

  for (final registry in registries) {
    try {
      // Skip local file registries
      if (_isLocalRegistryUrl(registry.url)) continue;

      final localMetadata = await registryManager.loadCachedMetadata(
        registry.id,
      );

      final hasUpdate = await registryManager.checkForUpdates(
        registry.url,
        local: localMetadata,
      );
      if (!hasUpdate) continue;

      Log.i(_tag, 'Applying update for registry: ${registry.id}');
      final metadata = await registryManager.fetchRegistryJson(registry.url);
      if (metadata == null) continue;

      await registryManager.syncRegistry(registry.id, registry.url);

      ref
          .read(registriesProvider.notifier)
          .updateRegistry(
            registry.id,
            registry.copyWith(
              pendingUpdate: false,
              lastFetchedAt: DateTime.now().millisecondsSinceEpoch,
              lastUpdated: metadata.updated,
              name: metadata.name ?? registry.name,
            ),
          );
      updatedCount++;
    } catch (e) {
      Log.w(_tag, 'Update failed for ${registry.id}: $e');
    }
  }

  if (updatedCount > 0) {
    ref.invalidate(availableProvidersProvider);
    // Drop loaded JS instances so the updated provider code takes effect
    // without an app restart.
    ref.invalidate(providerInstanceProvider);
    Log.ok(_tag, 'Updated $updatedCount registry(ies)');
  } else {
    Log.i(_tag, 'No registry updates available');
  }
  return updatedCount;
}

/// Remove a registry and its cached data.
Future<void> removeRegistry(String registryId, ProviderContainer ref) async {
  final registryManager = await ref.read(registryManagerProvider.future);

  // Delete the cached files first: if the delete fails, the registry is
  // still usable and loadable; removing it from the list while its cache
  // remains would leave a "ghost" provider that still resolves via
  // loadCachedProviderJs.
  final cacheDir = registryManager.registryDir(registryId);
  if (cacheDir.existsSync()) {
    try {
      cacheDir.deleteSync(recursive: true);
      Log.d(_tag, 'Deleted cached data for registry: $registryId');
    } catch (e) {
      Log.w(_tag, 'Failed to delete cached data for $registryId: $e');
    }
  }

  ref.read(registriesProvider.notifier).remove(registryId);
  ref.invalidate(providerInstanceProvider);
  Log.i(_tag, 'Removed registry: $registryId');
}

/// Toggle a provider's enabled state (convenience wrapper).
void toggleProvider(String providerId, ProviderContainer ref) {
  ref.read(enabledProvidersProvider.notifier).toggle(providerId);
}
