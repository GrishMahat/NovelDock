import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/models.dart';
import '../../../core/utils/logger.dart';
import '../../../theme/app_theme.dart';
import '../providers/provider_management_providers.dart';

const _tag = 'Registries';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registries'),
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
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'url',
                child: ListTile(
                  leading: Icon(Icons.cloud_download),
                  title: Text('Add from URL'),
                  subtitle: Text('From a GitHub repository'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'file',
                child: ListTile(
                  leading: Icon(Icons.file_open),
                  title: Text('Import JSON file'),
                  subtitle: Text('Load a local registry.json'),
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: registries.isEmpty
          ? _buildEmptyState(context, ref)
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: registries.length,
              itemBuilder: (context, index) {
                final registry = registries[index];
                return _buildRegistryCard(context, ref, registry);
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
            'No registries added',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add a registry URL or import a JSON file\nto get started.',
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

  Widget _buildRegistryCard(
      BuildContext context, WidgetRef ref, RegistryInfo registry) {
    final hasUpdate = registry.pendingUpdate;
    final status = registry.status;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: name + status + actions + toggle
            Row(
              children: [
                // Name + status badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              registry.name ?? registry.id,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (status != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: _registryStatusColor(status).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: _registryStatusColor(status),
                                ),
                              ),
                            ),
                          ],
                          if (hasUpdate) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text(
                                'UPDATE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (registry.description != null && registry.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            registry.description!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.kTextSecondaryDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                // Actions
                if (hasUpdate)
                  IconButton(
                    icon: const Icon(Icons.update, color: Colors.orange, size: 20),
                    tooltip: 'Update available',
                    onPressed: () => _confirmApplyUpdate(context, ref, registry),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Remove registry',
                  onPressed: () => _confirmRemoveRegistry(context, ref, registry),
                ),
                // Enable toggle
                Switch(
                  value: registry.enabled,
                  onChanged: (_) async {
                    await ref.read(registriesProvider.notifier).toggleRegistry(registry.id);
                  },
                ),
              ],
            ),

            // URL
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                registry.url,
                style: const TextStyle(fontSize: 11, color: AppTheme.kTextSecondaryDark),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  // ─── Import registry from local .json file ──────────────

  Future<void> _importRegistryFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

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
        const SnackBar(content: Text('Registry imported')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to import registry'),
          backgroundColor: Colors.red,
        ),
      );
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
        const SnackBar(content: Text('Registry added')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to fetch registry'),
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
          'Update "${registry.name ?? registry.id}"?\n\nThis will re-download all provider files.',
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
          'Remove "${registry.name ?? registry.id}"?\n\nThis will remove all cached provider data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
