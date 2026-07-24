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

const _tag = 'FileLoader';

class ProviderManagementPage extends ConsumerWidget {
  const ProviderManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registries = ref.watch(registriesProvider);
    final providersAsync = ref.watch(availableProvidersProvider);
    final enabledProviders = ref.watch(enabledProvidersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Providers'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'registry') {
                _showAddRegistryDialog(context, ref);
              } else if (value == 'file') {
                _loadProviderFromFile(context, ref);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'registry',
                child: ListTile(
                  leading: Icon(Icons.cloud_download),
                  title: Text('Add Registry'),
                  subtitle: Text('From GitHub repository'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'file',
                child: ListTile(
                  leading: Icon(Icons.file_open),
                  title: Text('Load from File'),
                  subtitle: Text('Load a local .js provider file'),
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
                        'No providers found.\nAdd a registry or load from a file.',
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
            'Add a registry or load a .js file\nto get started.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.kTextSecondaryDark),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showAddRegistryDialog(context, ref),
                icon: const Icon(Icons.cloud_download, size: 18),
                label: const Text('Add Registry'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => _loadProviderFromFile(context, ref),
                icon: const Icon(Icons.file_open, size: 18),
                label: const Text('Load from File'),
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
    return ListTile(
      leading: const Icon(Icons.folder),
      title: Text(registry.name ?? registry.id),
      subtitle: Text(
        registry.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmRemoveRegistry(context, ref, registry),
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
      secondary: _buildProviderIcon(provider),
      title: Text(provider.name),
      subtitle: Text(
        '${provider.lang.toUpperCase()} · ${provider.baseUrl}',
        style: const TextStyle(fontSize: 12),
      ),
      value: isEnabled,
      onChanged: (_) => toggleProvider(provider.id, ref),
    );
  }

  Widget _buildProviderIcon(ProviderMeta provider) {
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

  // ─── Load provider from local .js file ──────────────────

  Future<void> _loadProviderFromFile(BuildContext context, WidgetRef ref) async {
    print('[ProviderManagement] Opening file picker...');
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

      // Save the JS file to the providers directory
      final config = await AppConfig.getInstance();
      Log.i(_tag, 'Providers dir: ${config.providersDir.path}');

      final providerDir = config.providerDir(id);
      await providerDir.create(recursive: true);
      Log.i(_tag, 'Created provider dir: ${providerDir.path}');

      final jsFile = File(config.providerJsPath(id));
      await jsFile.writeAsString(content);
      Log.ok(_tag, 'Wrote JS file: ${jsFile.path}');

      // Save basic metadata
      final infoFile = File(config.providerInfoPath(id));
      await infoFile.writeAsString('''
{
  "id": "$id",
  "name": "$filename",
  "lang": "en",
  "baseUrl": "",
  "file": "${file.name}",
  "version": "0.0.1",
  "author": "local",
  "repo": null
}
''');

      // Enable the provider
      toggleProvider(id, ref);

      // Force the provider list to refresh
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

  // ─── Add registry from GitHub ───────────────────────────

  void _showAddRegistryDialog(BuildContext context, WidgetRef ref) {
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
              'Enter a GitHub repository URL containing metadata.json:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'https://github.com/user/repo',
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
}
