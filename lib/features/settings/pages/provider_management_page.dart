import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/models.dart';
import '../../../core/utils/logger.dart';
import '../../../widgets/shimmer_list.dart';
import '../providers/provider_management_providers.dart';

const _tag = 'Registries';

class ProviderManagementPage extends ConsumerStatefulWidget {
  const ProviderManagementPage({super.key});

  @override
  ConsumerState<ProviderManagementPage> createState() => _ProviderManagementPageState();
}

class _ProviderManagementPageState extends ConsumerState<ProviderManagementPage> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final registriesAsync = ref.watch(registriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registries'),
        actions: [
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
      body: registriesAsync.when(
        loading: () => const ShimmerList(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (registries) => registries.isEmpty
            ? _buildEmptyState(context, ref)
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: registries.length,
                itemBuilder: (context, index) {
                  final registry = registries[index];
                  return _buildRegistryCard(context, ref, registry);
                },
              ),
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
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No registries added',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a registry URL or import a JSON file\nto get started.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                        ],
                      ),
                      if (registry.description != null && registry.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            registry.description!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                // Actions
                IconButton(
                  icon: const Icon(Icons.update, size: 20),
                  tooltip: 'Check & update registry',
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
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
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
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  // ─── Import registry from local .json file ──────────────

  Future<void> _importRegistryFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result.isEmpty) return;

    final file = result.first;
    if (file.path == null) return;

    Log.i(_tag, 'Selected registry file: ${file.path}');
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Importing registry...')),
    );

    final error = await addRegistryFromFile(file.path!, ref);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registry imported')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error, style: const TextStyle(fontSize: 13)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  // ─── Add registry from URL ──────────────────────────────

  void _showAddRegistryUrlDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    ValueNotifier<bool> loading = ValueNotifier(false);
    ValueNotifier<String?> errorMsg = ValueNotifier(null);

    showDialog(
      context: context,
      builder: (context) => ValueListenableBuilder(
        valueListenable: loading,
        builder: (context, isLoading, _) => AlertDialog(
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
                enabled: !isLoading,
                decoration: const InputDecoration(
                  hintText: 'https://raw.githubusercontent.com/user/repo/main/registry.json',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              if (isLoading) ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Fetching registry...'),
                  ],
                ),
              ],
              ValueListenableBuilder(
                valueListenable: errorMsg,
                builder: (context, error, _) {
                  if (error == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              error,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final url = controller.text.trim();
                      if (url.isEmpty) return;
                      loading.value = true;
                      errorMsg.value = null;
                      final error = await addRegistry(url, ref);
                      loading.value = false;
                      if (error == null) {
                        if (context.mounted) Navigator.pop(context);
                      } else {
                        errorMsg.value = error;
                      }
                    },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
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
      const SnackBar(content: Text('Checking for updates...')),
    );

    final success = await updateRegistryNow(registry.id, ref);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registry updated')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registry is up to date')),
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
