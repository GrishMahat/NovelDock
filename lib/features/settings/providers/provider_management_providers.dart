import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/providers/models.dart';
import '../../../core/providers/registry.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/utils/logger.dart';

const _tag = 'Providers';

/// List of registries the user has added.
final registriesProvider =
    StateProvider<List<RegistryInfo>>((ref) => []);

/// All available providers — from registries AND local files.
final availableProvidersProvider =
    FutureProvider<List<ProviderMeta>>((ref) async {
  final registries = ref.watch(registriesProvider);
  final registryManager = await ref.watch(registryManagerProvider.future);
  final config = await AppConfig.getInstance();

  Log.i(_tag, 'Scanning for providers...');
  Log.i(_tag, 'Providers dir: ${config.providersDir.path}');

  final allProviders = <ProviderMeta>[];

  // 1. Load from registries
  Log.i(_tag, 'Registries: ${registries.length}');
  for (final registry in registries) {
    final metadata = await registryManager.loadCachedMetadata(registry.id);
    if (metadata != null) {
      Log.i(_tag, 'Got ${metadata.providers.length} providers from registry "${registry.id}"');
      allProviders.addAll(metadata.providers);
    }
  }

  // 2. Load from local providers directory (loaded from file)
  final providersDir = config.providersDir;
  if (await providersDir.exists()) {
    Log.i(_tag, 'Scanning local providers directory...');
    await for (final entity in providersDir.list()) {
      if (entity is! Directory) continue;
      final dirName = p.basename(entity.path);
      final infoFile = File(p.join(entity.path, 'info.json'));
      if (await infoFile.exists()) {
        try {
          final content = await infoFile.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;
          final meta = ProviderMeta.fromJson(json);
          if (!allProviders.any((p) => p.id == meta.id)) {
            Log.i(_tag, 'Loaded local provider: ${meta.name} (${meta.id})');
            allProviders.add(meta);
          } else {
            Log.d(_tag, 'Skipping duplicate: ${meta.id}');
          }
        } catch (e) {
          Log.e(_tag, 'Error parsing info.json in $dirName', e);
        }
      }
    }
  } else {
    Log.w(_tag, 'Local providers directory does not exist');
  }

  Log.ok(_tag, 'Total providers found: ${allProviders.length}');
  return allProviders;
});

/// Set of enabled provider IDs — persisted to settings table.
final enabledProvidersProvider =
    StateNotifierProvider<EnabledProvidersNotifier, Set<String>>((ref) {
  return EnabledProvidersNotifier(ref);
});

class EnabledProvidersNotifier extends StateNotifier<Set<String>> {
  final Ref ref;

  EnabledProvidersNotifier(this.ref) : super(const {}) {
    _loadFromDb();
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
    }
  }

  Future<void> _saveToDb() async {
    try {
      final settingsDao = ref.read(settingsDaoProvider);
      await settingsDao.setSetting('enabled_providers', jsonEncode(state.toList()));
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

/// Add a new registry: fetch metadata, sync providers, add to list.
Future<bool> addRegistry(String url, WidgetRef ref) async {
  final registryManager = await ref.read(registryManagerProvider.future);

  final id = Uri.parse(url).pathSegments
      .where((s) => s.isNotEmpty)
      .join('-');

  Log.i(_tag, 'Adding registry: $url (id: $id)');
  final metadata = await registryManager.fetchMetadata(url);
  if (metadata == null) {
    Log.e(_tag, 'Failed to fetch metadata from $url');
    return false;
  }

  await registryManager.syncRegistry(id, url);

  final current = ref.read(registriesProvider);
  final registry = RegistryInfo(
    id: id,
    url: url,
    name: id,
    enabled: true,
    lastFetchedAt: DateTime.now().millisecondsSinceEpoch,
  );

  ref.read(registriesProvider.notifier).state = [...current, registry];
  Log.ok(_tag, 'Registry added: $id');
  return true;
}

/// Remove a registry and its cached data.
void removeRegistry(String registryId, WidgetRef ref) {
  final current = ref.read(registriesProvider);
  ref.read(registriesProvider.notifier).state =
      current.where((r) => r.id != registryId).toList();
  Log.i(_tag, 'Removed registry: $registryId');
}

/// Toggle a provider's enabled state (convenience wrapper).
void toggleProvider(String providerId, WidgetRef ref) {
  ref.read(enabledProvidersProvider.notifier).toggle(providerId);
}
