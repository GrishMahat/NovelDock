import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/models.dart';
import '../../core/utils/platform.dart';
import '../../theme/tokens.dart';
import '../../widgets/error_view.dart';
import '../../widgets/header_search_field.dart';
import '../../widgets/max_width_box.dart';
import '../../widgets/page_header.dart';
import '../../widgets/provider_avatar.dart';
import '../../widgets/shimmer_list.dart';
import '../../core/providers/registries.dart';
import '../settings/pages/general_settings_page.dart';
import 'webview_screen.dart';

/// Browse screen. Installed tab for browsing sources, Catalog tab for
/// install/uninstall.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isSearching = false;
  bool _updating = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _updateAll() async {
    setState(() => _updating = true);
    try {
      final count = await updateAllRegistries(ref.container);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        count > 0
            ? SnackBar(content: Text('Updated $count registry(ies)'))
            : const SnackBar(content: Text('All extensions are up to date')),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _submitGlobalSearch(String q) {
    final query = q.trim();
    if (query.isEmpty) return;
    context.push('/search/results?q=${Uri.encodeComponent(query)}');
    _searchController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return Scaffold(
        body: Column(
          children: [
            PageHeader(
              title: 'Browse',
              search: HeaderSearchField(
                hint: 'Search all sources',
                controller: _searchController,
                onChanged: (_) {},
                onSubmitted: _submitGlobalSearch,
              ),
              actions: [
                if (_tabController.index == 1)
                  OutlinedButton.icon(
                    onPressed: _updating ? null : _updateAll,
                    icon: _updating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.update, size: 18),
                    label: Text(_updating ? 'Updating' : 'Update all'),
                  ),
              ],
              tabController: _tabController,
              tabs: [
                const Tab(text: 'Installed'),
                _catalogTab(),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  const InstalledTab(),
                  CatalogTab(
                    showUpdateAll: false,
                    updating: _updating,
                    onUpdateAll: _updateAll,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search all sources...',
                  border: InputBorder.none,
                ),
                onSubmitted: (q) => context.push('/search/results?q=$q'),
              )
            : const Text('Browse'),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
            )
          else
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
            const Tab(text: 'Installed'),
            _catalogTab(),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const InstalledTab(),
          CatalogTab(updating: _updating, onUpdateAll: _updateAll),
        ],
      ),
    );
  }

  Widget _catalogTab() {
    return Consumer(
      builder: (context, ref, _) {
        final providersAsync = ref.watch(availableProvidersProvider);
        final enabled = ref.watch(enabledProvidersProvider);
        return providersAsync.when(
          loading: () => const Tab(text: 'Catalog'),
          error: (_, _) => const Tab(text: 'Catalog'),
          data: (providers) {
            final installed = providers
                .where((p) => enabled.contains(p.id))
                .length;
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Catalog'),
                  if (installed > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$installed',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
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
// Installed Tab
// ═══════════════════════════════════════════════════════════

class InstalledTab extends ConsumerWidget {
  const InstalledTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(availableProvidersProvider);
    final enabled = ref.watch(enabledProvidersProvider);
    // "Show NSFW Sources" general setting: hide 18+ extensions unless
    // explicitly enabled (they were previously only badged, never filtered).
    final showNsfw = ref.watch(
      generalSettingsProvider.select((s) => s.showNsfw),
    );

    return providersAsync.when(
      loading: () => const ShimmerList(),
      error: (e, _) => ErrorView(
        message: 'Failed to load providers',
        onRetry: () => ref.invalidate(availableProvidersProvider),
      ),
      data: (providers) {
        final enabledProviders = providers
            .where((p) => enabled.contains(p.id) && (showNsfw || !p.nsfw))
            .toList();

        if (enabledProviders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.explore_off,
                  size: 64,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  'No sources installed',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Go to the Catalog tab to add sources.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        final tier = screenSizeOf(context);

        // Scrollable: this grid is the whole tab body, so a bounded
        // shrinkWrap column made sources below the fold unreachable on a
        // phone while looking fine on a tall desktop window.
        return MaxWidthBox(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.lg,
            Insets.lg,
            Insets.xl,
          ),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _sectionHeader(
                  context,
                  'Installed (${enabledProviders.length})',
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: Insets.sm)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    // Fixed per tier: extent-derived counts gave phones a
                    // single 328dp-wide card per source per screen.
                    crossAxisCount: Grids.sourceColumns(tier),
                    crossAxisSpacing: Insets.sm,
                    mainAxisSpacing: Insets.sm,
                    mainAxisExtent: Grids.sourceExtent(tier),
                  ),
                  itemCount: enabledProviders.length,
                  itemBuilder: (context, index) =>
                      _SourceCard(provider: enabledProviders[index]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// Compact source card: logo, name, language, and a browse action.
class _SourceCard extends StatelessWidget {
  final ProviderMeta provider;
  const _SourceCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/provider/${provider.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.sm,
          ),
          child: Row(
            children: [
              ProviderAvatar(provider: provider, radius: 18),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      provider.lang.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Catalog Tab
// ═══════════════════════════════════════════════════════════

class CatalogTab extends ConsumerWidget {
  final bool showUpdateAll;
  final bool updating;
  final VoidCallback? onUpdateAll;

  const CatalogTab({
    super.key,
    this.showUpdateAll = true,
    this.updating = false,
    this.onUpdateAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(availableProvidersProvider);
    final enabled = ref.watch(enabledProvidersProvider);
    final showNsfw = ref.watch(
      generalSettingsProvider.select((s) => s.showNsfw),
    );

    return providersAsync.when(
      loading: () => const ShimmerList(),
      error: (e, _) => ErrorView(
        message: 'Failed to load catalog',
        onRetry: () => ref.invalidate(availableProvidersProvider),
      ),
      data: (providers) {
        final visible = showNsfw
            ? providers
            : providers.where((p) => !p.nsfw).toList();
        if (visible.isEmpty) {
          return const Center(
            child: Text('No providers found.\nAdd a registry to get started.'),
          );
        }

        // Only not-yet-installed sources. They used to be duplicated here and
        // in the Installed tab, so the same source appeared twice with two
        // different toggle affordances and no reason for the user to know
        // which list was authoritative. Installed has its own tab.
        final available = visible
            .where((p) => !enabled.contains(p.id))
            .toList();

        if (available.isEmpty) {
          return _CatalogAllInstalled(count: visible.length);
        }

        // Group available by language
        final grouped = <String, List<ProviderMeta>>{};
        for (final p in available) {
          final lang = p.lang.isEmpty ? 'Other' : p.lang.toUpperCase();
          grouped.putIfAbsent(lang, () => []).add(p);
        }

        return MaxWidthBox(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.md,
            Insets.lg,
            Insets.xl,
          ),
          child: ListView(
            children: [
              if (showUpdateAll)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.sm),
                  child: OutlinedButton.icon(
                    onPressed: updating ? null : onUpdateAll,
                    icon: updating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.update, size: 18),
                    label: Text(updating ? 'Updating...' : 'Update all'),
                  ),
                ),
              for (final entry in grouped.entries) ...[
                _sectionHeader(context, entry.key),
                ...entry.value.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: Insets.sm),
                    child: _ExtensionTile(
                      provider: p,
                      isInstalled: false,
                      onToggle: () => toggleProvider(p.id, ref.container),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, Insets.lg, 0, Insets.sm),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// Catalog with nothing left to install. Points at the tab that owns
/// installed sources instead of leaving a blank list.
class _CatalogAllInstalled extends StatelessWidget {
  final int count;
  const _CatalogAllInstalled({required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 56,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: Insets.md),
            Text(
              count == 0
                  ? 'No sources found'
                  : 'All $count source(s) installed',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.xs),
            Text(
              'Manage the ones you added in the Installed tab.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isInstalled
          ? scheme.primaryContainer.withValues(alpha: 0.18)
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(
          color: isInstalled ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // One row, one primary action: tapping the row installs or uninstalls,
      // which is what the switch implied and what people actually come here
      // to do. Details moved behind an explicit labelled button, because
      // "tap row opens a sheet, tap switch installs" made the switch feel
      // like the only real control and the row feel broken.
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: ProviderAvatar(provider: provider, radius: 18),
        title: Text(
          provider.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        subtitle: Text(
          '${provider.lang.toUpperCase()} · v${provider.version}'
          '${provider.nsfw ? ' · 18+' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        trailing: IconButton(
          icon: Icon(
            isInstalled ? Icons.check_circle : Icons.info_outline,
            size: 20,
            color: isInstalled ? scheme.primary : scheme.onSurfaceVariant,
          ),
          tooltip: isInstalled ? 'Installed — tap row to remove' : 'Details',
          onPressed: () => isInstalled
              ? onToggle()
              : _showProviderInfo(context, provider, isInstalled, onToggle),
        ),
        onTap: onToggle,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Provider info sheet (shared by Installed and Catalog tabs)
// ═══════════════════════════════════════════════════════════

void _showProviderInfo(
  BuildContext context,
  ProviderMeta provider,
  bool isInstalled,
  VoidCallback onToggle,
) {
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
                ProviderAvatar(provider: provider),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        provider.baseUrl,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Info section
          _infoTile(
            context,
            Icons.language,
            'Language',
            provider.lang.toUpperCase(),
          ),
          _infoTile(context, Icons.code, 'Version', provider.version),
          if (provider.author != null)
            _infoTile(
              context,
              Icons.person_outline,
              'Author',
              provider.author!,
            ),
          if (provider.nsfw)
            _infoTile(context, Icons.warning_amber, 'Content', 'NSFW (18+)'),
          if (provider.registryId != null)
            _infoTile(
              context,
              Icons.folder_open,
              'Registry',
              provider.registryId!,
            ),

          const Divider(height: 1),

          // Actions
          SwitchListTile(
            secondary: const Icon(Icons.download_done),
            title: const Text('Installed'),
            value: isInstalled,
            onChanged: (_) {
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
        ],
      ),
    ),
  );
}

Widget _infoTile(
  BuildContext context,
  IconData icon,
  String label,
  String value,
) {
  return ListTile(
    leading: Icon(
      icon,
      size: 20,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    title: Text(label, style: Theme.of(context).textTheme.bodySmall),
    subtitle: Text(value),
    dense: true,
  );
}
