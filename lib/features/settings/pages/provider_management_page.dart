import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_config.dart';
import '../../../core/providers/models.dart';
import '../../../core/utils/logger.dart';
import '../../../theme/app_theme.dart';
import '../providers/provider_management_providers.dart';

const _tag = 'ProviderMgmt';

class ProviderManagementPage extends ConsumerStatefulWidget {
  const ProviderManagementPage({super.key});

  @override
  ConsumerState<ProviderManagementPage> createState() => _ProviderManagementPageState();
}

class _ProviderManagementPageState extends ConsumerState<ProviderManagementPage> {
  bool _checkingUpdates = false;

  @override
  void initState() {
    super.initState();
    _checkUpdatesOnStartup();
  }

  Future<void> _checkUpdatesOnStartup() async {
    setState(() => _checkingUpdates = true);
    try {
      final updatedIds = await checkAllRegistryUpdates(ref);
      if (mounted && updatedIds.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${updatedIds.length} registry(ies) have updates available'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () {}, // Already on this page
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registriesAsync = ref.watch(registriesProvider);
    final registries = registriesAsync.value ?? [];
    final providersAsync = ref.watch(availableProvidersProvider);
    final enabledProviders = ref.watch(enabledProvidersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Providers'),
        actions: [
          if (_checkingUpdates)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'url') {
                _showAddRegistryUrlDialog(context, ref);
              } else if (value == 'file') {
                _importRegistryFile(context, ref);
              } else if (value == 'js') {
                _loadProviderFromFile(context, ref);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'url',
                child: ListTile(
                  leading: Icon(Icons.cloud_download),
                  title: Text('Add Registry URL'),
                  subtitle: Text('From a GitHub repository'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'file',
                child: ListTile(
                  leading: Icon(Icons.file_open),
                  title: Text('Import Registry JSON'),
                  subtitle: Text('Load a local registry.json file'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'js',
                child: ListTile(
                  leading: Icon(Icons.code),
                  title: Text('Load Provider JS'),
                  subtitle: Text('Load a single provider .js file'),
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: providersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (providers) {
          if (registries.isEmpty && providers.isEmpty) {
            return _buildEmptyState(context, ref);
          }

          return CustomScrollView(
            slivers: [
              // Registries section
              if (registries.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _buildSectionHeader('Registries'),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final registry = registries[index];
                      return _buildRegistryTile(context, ref, registry);
                    },
                    childCount: registries.length,
                  ),
                ),
              ],

              // Providers section
              SliverToBoxAdapter(
                child: _buildSectionHeader('Available Providers'),
              ),
              if (providers.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No providers found.\nAdd a registry or load a .js file.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.kTextSecondaryDark),
                      ),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final provider = providers[index];
                      final isEnabled =
                          enabledProviders.contains(provider.id);
                      return _buildProviderTile(
                          context, ref, provider, isEnabled);
                    },
                    childCount: providers.length,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off,
            size: 64,
            color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No providers loaded',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add a registry URL, import a JSON file,\nor load a .js provider to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.kTextSecondaryDark),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showAddRegistryUrlDialog(context, ref),
                icon: const Icon(Icons.cloud_download, size: 18),
                label: const Text('Add URL'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _importRegistryFile(context, ref),
                icon: const Icon(Icons.file_open, size: 18),
                label: const Text('Import JSON'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.kTextSecondaryDark,
        ),
      ),
    );
  }

  Widget _buildRegistryTile(
      BuildContext context, WidgetRef ref, RegistryInfo registry) {
    final hasUpdate = registry.pendingUpdate;
    final status = registry.status;

    return ListTile(
      leading: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            _registryStatusIcon(status),
            color: _registryStatusColor(status),
          ),
          if (hasUpdate)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      title: Text(registry.name ?? registry.id),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (registry.description != null && registry.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                registry.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              registry.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.kTextSecondaryDark),
            ),
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _registryStatusColor(status).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _registryStatusColor(status),
                  ),
                ),
              ),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasUpdate)
            IconButton(
              icon: const Icon(Icons.update, color: Colors.orange),
              tooltip: 'Update available',
              onPressed: () => _confirmApplyUpdate(context, ref, registry),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmRemoveRegistry(context, ref, registry),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderTile(
    BuildContext context,
    WidgetRef ref,
    ProviderMeta provider,
    bool isEnabled,
  ) {
    return SwitchListTile(
      secondary: _buildProviderAvatar(provider),
      title: Row(
        children: [
          Expanded(child: Text(provider.name)),
          if (provider.nsfw)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'NSFW',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              '${provider.lang.toUpperCase()} · ${provider.baseUrl}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (provider.registryId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                provider.registryId!,
                style: const TextStyle(fontSize: 9, color: AppTheme.kTextSecondaryDark),
              ),
            ),
        ],
      ),
      value: isEnabled,
      onChanged: (_) => toggleProvider(provider.id, ref),
    );
  }

  Widget _buildProviderAvatar(ProviderMeta provider) {
    // Try to load cached icon
    final iconFile = _getCachedIcon(provider.id);
    if (iconFile != null) {
      return CircleAvatar(
        backgroundImage: FileImage(iconFile),
        backgroundColor: Colors.transparent,
      );
    }

    // Fallback to letter avatar
    final color = Color(
      provider.name.hashCode.toUnsigned(32) | 0xFF000000,
    ).withValues(alpha: 0.7);

    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.2),
      child: Text(
        provider.name.isNotEmpty ? provider.name[0].toUpperCase() : '?',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  File? _getCachedIcon(String providerId) {
    // Search registries for the provider's icon
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    final registriesDir = Directory('$home/.config/quicknovel/registries');
    if (!registriesDir.existsSync()) return null;

    for (final entity in registriesDir.listSync()) {
      if (entity is! Directory) continue;
      final registryDir = entity.path;
      final metadataFile = File('$registryDir/metadata.json');
      if (!metadataFile.existsSync()) continue;

      try {
        final json = jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
        final providers = json['providers'] as List? ?? [];
        for (final p in providers) {
          if (p['id'] == providerId && p['icon'] != null) {
            final iconPath = '$registryDir/${p['icon']}';
            final file = File(iconPath);
            if (file.existsSync()) return file;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  // ─── Import registry from local .json file ──────────────

  Future<void> _importRegistryFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) {
      Log.d(_tag, 'File picker cancelled');
      return;
    }

    final file = result.files.first;
    if (file.path == null) {
      Log.e(_tag, 'File path is null');
      return;
    }

    Log.i(_tag, 'Selected registry file: ${file.path}');
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Importing registry...')),
    );

    final success = await addRegistryFromFile(file.path!, ref);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registry imported successfully')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to import registry. Check the JSON format.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ─── Load provider from local .js file ──────────────────

  Future<void> _loadProviderFromFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['js'],
    );

    if (result == null || result.files.isEmpty) {
      Log.d(_tag, 'File picker cancelled');
      return;
    }

    final file = result.files.first;
    if (file.path == null) {
      Log.e(_tag, 'File path is null');
      return;
    }

    Log.i(_tag, 'Selected file: ${file.path}');

    try {
      final content = await File(file.path!).readAsString();
      Log.i(_tag, 'Read ${content.length} bytes from file');

      final filename = p.basenameWithoutExtension(file.path!);
      final id = filename.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
      Log.i(_tag, 'Provider ID: $id');

      final config = await AppConfig.getInstance();
      final providerDir = config.providerDir(id);
      await providerDir.create(recursive: true);

      final jsFile = File(config.providerJsPath(id));
      await jsFile.writeAsString(content);

      // Create a local registry with this single provider
      final registryId = 'local_$id';
      final metadata = RegistryMetadata(
        name: filename,
        providers: [
          ProviderMeta(
            id: id,
            name: filename,
            lang: 'en',
            baseUrl: '',
            file: '$id.js',
            version: '0.0.1',
            author: 'local',
          ),
        ],
      );
      final metadataFile = File(config.registryMetadataPath(registryId));
      await metadataFile.parent.create(recursive: true);
      await metadataFile.writeAsString(jsonEncode(metadata.toJson()));

      toggleProvider(id, ref);
      ref.invalidate(availableProvidersProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded provider: $filename')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ─── Add registry from URL ──────────────────────────────

  void _showAddRegistryUrlDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Registry'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the raw URL to a registry.json file:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'https://raw.githubusercontent.com/user/repo/main/registry.json',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isEmpty) return;

              Navigator.pop(context);
              await _addRegistry(context, ref, url);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _addRegistry(
      BuildContext context, WidgetRef ref, String url) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fetching registry...')),
    );

    final success = await addRegistry(url, ref);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registry added successfully')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to fetch registry. Check the URL.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ─── Update registry ────────────────────────────────────

  void _confirmApplyUpdate(
      BuildContext context, WidgetRef ref, RegistryInfo registry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Registry'),
        content: Text(
          'Update "${registry.name ?? registry.id}"?\n\n'
          'This will re-download all provider files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await _applyUpdate(context, ref, registry);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyUpdate(
      BuildContext context, WidgetRef ref, RegistryInfo registry) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Updating registry...')),
    );

    final success = await applyRegistryUpdate(registry.id, ref);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registry updated')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update registry'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ─── Remove registry ────────────────────────────────────

  void _confirmRemoveRegistry(
      BuildContext context, WidgetRef ref, RegistryInfo registry) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Registry'),
        content: Text(
          'Remove "${registry.name ?? registry.id}"?\n\n'
          'This will remove the cached provider data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              removeRegistry(registry.id, ref);
              Navigator.pop(context);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  // ─── Registry status helpers ──────────────────────────────

  IconData _registryStatusIcon(String? status) {
    switch (status) {
      case 'active':
        return Icons.check_circle;
      case 'unmaintained':
        return Icons.warning_amber;
      case 'deprecated':
        return Icons.error;
      default:
        return Icons.folder;
    }
  }

  Color _registryStatusColor(String? status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'unmaintained':
        return Colors.orange;
      case 'deprecated':
        return Colors.red;
      default:
        return AppTheme.kTextSecondaryDark;
    }
  }
}
