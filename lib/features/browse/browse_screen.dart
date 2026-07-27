import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/error_view.dart';
import '../../widgets/shimmer_list.dart';
import '../settings/providers/provider_management_providers.dart';
import 'webview_screen.dart';

/// Browse screen — Sources tab for browsing providers, Extensions tab for install/uninstall.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search sources...',
                  border: InputBorder.none,
                ),
                onSubmitted: (q) => context.push('/search/results?q=$q'),
              )
            : const Text('Browse'),
        actions: [
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () {},
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                });
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Sources'),
            _extensionsTab(),
            const Tab(text: 'Migrate'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const SourcesTab(),
          const ExtensionsTab(),
          const Center(child: Text('Migrate — coming soon')),
        ],
      ),
    );
  }

  Widget _extensionsTab() {
    return Consumer(
      builder: (context, ref, _) {
        final providersAsync = ref.watch(availableProvidersProvider);
        final enabled = ref.watch(enabledProvidersProvider);
        return providersAsync.when(
          loading: () => const Tab(text: 'Extensions'),
          error: (_, __) => const Tab(text: 'Extensions'),
          data: (providers) {
            final installed = providers.where((p) => enabled.contains(p.id)).length;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Extensions'),
                  if (installed > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$installed',
                        style: const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Sources Tab
// ═══════════════════════════════════════════════════════════

class SourcesTab extends ConsumerWidget {
  const SourcesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(availableProvidersProvider);
    final enabled = ref.watch(enabledProvidersProvider);

    return providersAsync.when(
      loading: () => const ShimmerList(),
      error: (e, _) => ErrorView(
        message: 'Failed to load providers',
        onRetry: () => ref.invalidate(availableProvidersProvider),
      ),
      data: (providers) {
        final enabledProviders =
            providers.where((p) => enabled.contains(p.id)).toList();

        if (enabledProviders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.explore_off,
                    size: 64, color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                const Text('No sources installed',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'Go to Extensions tab to install providers.',
                  style: TextStyle(color: AppTheme.kTextSecondaryDark),
                ),
              ],
            ),
          );
        }

        return ListView(
          children: [
            _sectionHeader(context, 'Installed (${enabledProviders.length})'),
            ...enabledProviders.map((p) => _SourceTile(provider: p)),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final ProviderMeta provider;
  const _SourceTile({required this.provider});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: providerAvatar(provider),
      title: Text(provider.name),
      subtitle: Text(
        provider.lang.toUpperCase(),
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Latest',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.push_pin, size: 18, color: Theme.of(context).colorScheme.primary),
        ],
      ),
      onTap: () => context.push('/provider/${provider.id}'),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Extensions Tab
// ═══════════════════════════════════════════════════════════

class ExtensionsTab extends ConsumerWidget {
  const ExtensionsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(availableProvidersProvider);
    final enabled = ref.watch(enabledProvidersProvider);

    return providersAsync.when(
      loading: () => const ShimmerList(),
      error: (e, _) => ErrorView(
        message: 'Failed to load extensions',
        onRetry: () => ref.invalidate(availableProvidersProvider),
      ),
      data: (providers) {
        if (providers.isEmpty) {
          return const Center(
            child: Text('No providers found.\nAdd a registry to get started.'),
          );
        }

        final installed = providers.where((p) => enabled.contains(p.id)).toList();
        final available = providers.where((p) => !enabled.contains(p.id)).toList();

        // Group available by language
        final grouped = <String, List<ProviderMeta>>{};
        for (final p in available) {
          final lang = p.lang.isEmpty ? 'Other' : p.lang.toUpperCase();
          grouped.putIfAbsent(lang, () => []).add(p);
        }

        return ListView(
          children: [
            if (installed.isNotEmpty) ...[
              _sectionHeader(context, 'Installed'),
              ...installed.map((p) => _ExtensionTile(
                    provider: p,
                    isInstalled: true,
                    onToggle: () => toggleProvider(p.id, ref),
                  )),
            ],
            for (final entry in grouped.entries) ...[
              _sectionHeader(context, entry.key),
              ...entry.value.map((p) => _ExtensionTile(
                    provider: p,
                    isInstalled: false,
                    onToggle: () => toggleProvider(p.id, ref),
                  )),
            ],
          ],
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ExtensionTile extends StatelessWidget {
  final ProviderMeta provider;
  final bool isInstalled;
  final VoidCallback onToggle;

  const _ExtensionTile({
    required this.provider,
    required this.isInstalled,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: providerAvatar(provider),
      title: Text(provider.name),
      subtitle: Row(
        children: [
          Text(
            '${provider.lang.toUpperCase()} · v${provider.version}',
            style: const TextStyle(fontSize: 12),
          ),
          if (provider.nsfw) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                '18+',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ),
          ],
        ],
      ),
      trailing: isInstalled
          ? IconButton(
              icon: const Icon(Icons.settings, size: 20),
              onPressed: () => _showSettings(context),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.language, size: 20, color: AppTheme.kTextSecondaryDark),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WebViewScreen(
                          url: provider.baseUrl,
                          title: provider.name,
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.download, size: 20),
                  onPressed: onToggle,
                ),
              ],
            ),
      onTap: isInstalled ? () => context.push('/provider/${provider.id}') : null,
    );
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  providerAvatar(provider),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          provider.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          provider.baseUrl,
                          style: const TextStyle(fontSize: 12, color: AppTheme.kTextSecondaryDark),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Info section
            _infoTile(Icons.language, 'Language', provider.lang.toUpperCase()),
            _infoTile(Icons.code, 'Version', provider.version),
            if (provider.author != null)
              _infoTile(Icons.person_outline, 'Author', provider.author!),
            if (provider.nsfw)
              _infoTile(Icons.warning_amber, 'Content', 'NSFW (18+)'),
            if (provider.registryId != null)
              _infoTile(Icons.folder_open, 'Registry', provider.registryId!),

            const Divider(height: 1),

            // Actions
            SwitchListTile(
              secondary: const Icon(Icons.download_done),
              title: const Text('Installed'),
              value: true,
              onChanged: (val) {
                Navigator.pop(context);
                onToggle();
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('Open homepage'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WebViewScreen(
                      url: provider.baseUrl,
                      title: provider.name,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Uninstall', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                onToggle();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, size: 20, color: AppTheme.kTextSecondaryDark),
      title: Text(label, style: const TextStyle(fontSize: 12)),
      subtitle: Text(value),
      dense: true,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Shared — provider avatar with icon from registry
// ═══════════════════════════════════════════════════════════

Widget providerAvatar(ProviderMeta provider) {
  // Use AppConfig's platform-aware registries directory
  try {
    final registriesDir = Directory(_resolveRegistriesDir());
    if (registriesDir.existsSync()) {
      for (final entity in registriesDir.listSync()) {
        if (entity is! Directory) continue;
        final metadataFile = File('${entity.path}/metadata.json');
        if (!metadataFile.existsSync()) continue;
        try {
          final json = jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
          final providers = json['providers'] as List? ?? [];
          for (final p in providers) {
            if (p['id'] == provider.id && p['icon'] != null) {
              final iconFile = File('${entity.path}/icons/${provider.id}.png');
              if (iconFile.existsSync()) {
                return CircleAvatar(
                  backgroundImage: FileImage(iconFile),
                  backgroundColor: Colors.transparent,
                );
              }
            }
          }
        } catch (_) {}
      }
    }
  } catch (_) {}

  // Fallback to letter avatar
  final color = Color(
    provider.name.hashCode.toUnsigned(32) | 0xFF000000,
  ).withValues(alpha: 0.7);

  return CircleAvatar(
    backgroundColor: color.withValues(alpha: 0.2),
    child: Text(
      provider.name.isNotEmpty ? provider.name[0].toUpperCase() : '?',
      style: TextStyle(color: color, fontWeight: FontWeight.bold),
    ),
  );
}

/// Resolves the registries directory path in a platform-aware manner,
/// mirroring the logic in [AppConfig._resolveConfigDir].
String _resolveRegistriesDir() {
  if (Platform.isLinux) {
    final home = Platform.environment['HOME'];
    if (home != null) return '$home/.config/noveldock/registries';
  }
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null) return '$home/Library/Application Support/noveldock/registries';
  }
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null) return '$appData/noveldock/registries';
  }
  // Android/iOS: registry metadata is not stored locally in the same way;
  // the letter-avatar fallback is appropriate on mobile.
  return '';
}
