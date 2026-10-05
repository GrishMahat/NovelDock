import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/models.dart';
import '../../core/utils/platform.dart';
import '../../theme/tokens.dart';
import '../../widgets/add_default_providers_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/error_view.dart';
import '../../widgets/header_search_field.dart';
import '../../widgets/max_width_box.dart';
import '../../widgets/page_header.dart';
import '../../widgets/provider_avatar.dart';
import '../../widgets/shimmer_list.dart';
import '../../core/providers/registries.dart';
import '../settings/pages/general_settings_page.dart';
import 'webview_screen.dart';

/// Browse screen. Installed tab for browsing and removing sources, Catalog tab
/// for adding them.
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
          // Nothing installed. With no registries at all there is nothing to
          // install, so point at the default add; with a populated catalog the
          // Catalog tab is the answer and this stays a pointer to it.
          final noRegistries = providers.isEmpty;
          return EmptyState(
            icon: noRegistries ? Icons.cloud_off : Icons.explore_off,
            title: noRegistries ? 'No sources yet' : 'No sources installed',
            subtitle: noRegistries
                ? 'NovelDock has no sources to browse. Add the default set to '
                      'get started.'
                : 'Go to the Catalog tab to add sources.',
            action: noRegistries
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AddDefaultProvidersButton(),
                      const SizedBox(height: Insets.sm),
                      TextButton.icon(
                        onPressed: () => context.push('/settings/providers'),
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Manage registries'),
                      ),
                    ],
                  )
                : null,
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
///
/// Purely a browse surface — tapping opens the source. It deliberately has no
/// verb of its own: a per-card overflow menu meant uninstall lived only behind
/// three dots here, one tap deeper than the tap that installed the source.
/// Both verbs live in the Catalog, where the whole list is visible at once.
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

/// Uninstall an installed source, after confirming.
///
/// Uninstall only clears the enabled flag: the source leaves Browse and Search,
/// while library books, downloads and history keep working because they
/// resolve the provider by id straight from the registry cache. So this is
/// reversible rather than a data delete — but it is still one tap on a list of
/// 27-odd rows, hence the dialog plus Undo.
Future<void> _confirmUninstallSource(
  BuildContext context,
  ProviderContainer container,
  ProviderMeta provider,
) async {
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Uninstall ${provider.name}?'),
      content: const Text(
        'The source leaves Browse and Search. Books you already added, their '
        'downloads and your history stay. You can install it again from this '
        'Catalog at any time.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Uninstall'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  setProviderEnabled(provider.id, false, container);

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('Uninstalled ${provider.name}'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => setProviderEnabled(provider.id, true, container),
      ),
    ),
  );
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
          // No catalog at all: the most likely cause is zero registries, so
          // offer the one-click default add instead of only explaining that a
          // registry is needed somewhere else.
          return EmptyState(
            icon: Icons.cloud_off,
            title: 'No sources found',
            subtitle:
                'Add the default providers, or point NovelDock at your own '
                'registry.',
            action: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AddDefaultProvidersButton(),
                const SizedBox(height: Insets.sm),
                TextButton.icon(
                  onPressed: () => context.push('/settings/providers'),
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Manage registries'),
                ),
              ],
            ),
          );
        }

        // Every source, installed or not. This list is the app's source
        // management surface: whichever verb you need — install or uninstall —
        // is here, on the row, spelled out. Hiding installed sources (they were
        // filtered out) meant the row you tapped to install simply vanished and
        // the reverse verb lived nowhere; splitting the two states across two
        // tabs meant the same source showed up twice with no way to tell which
        // list was authoritative.
        final grouped = <String, List<ProviderMeta>>{};
        for (final p in visible) {
          final lang = p.lang.isEmpty ? 'Other' : p.lang.toUpperCase();
          grouped.putIfAbsent(lang, () => []).add(p);
        }

        final installedCount = visible
            .where((p) => enabled.contains(p.id))
            .length;

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
              Padding(
                padding: const EdgeInsets.only(bottom: Insets.xs),
                child: Text(
                  installedCount == 0
                      ? 'None installed yet'
                      : '$installedCount of ${visible.length} installed',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final entry in grouped.entries) ...[
                _sectionHeader(context, entry.key),
                ...entry.value.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: Insets.sm),
                    child: _ExtensionTile(
                      provider: p,
                      isInstalled: enabled.contains(p.id),
                      onInstall: () =>
                          setProviderEnabled(p.id, true, ref.container),
                      onUninstall: () =>
                          _confirmUninstallSource(context, ref.container, p),
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

/// Catalog row — the app's install/uninstall control.
///
/// One row, one visible verb, and the verb is written out: "Install" or
/// "Uninstall" on a labelled button. Not an icon, not a switch, and not
/// something hidden behind three dots. An installed row keeps the verb visible
/// rather than dropping out of the list, which is what makes this the one
/// place both directions are reachable.
///
/// The row itself does not toggle. Tapping a not-installed row installs, since
/// this list exists to be tapped; tapping an installed row opens its details,
/// because the destructive direction must always take the labelled button
/// rather than a stray tap somewhere in 27 rows.
class _ExtensionTile extends StatelessWidget {
  final ProviderMeta provider;
  final bool isInstalled;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;

  const _ExtensionTile({
    required this.provider,
    required this.isInstalled,
    required this.onInstall,
    required this.onUninstall,
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
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: ProviderAvatar(provider: provider, radius: 18),
        title: Row(
          children: [
            // State is readable without tapping anything, and not only from the
            // button label: the tick rides with the name.
            if (isInstalled) ...[
              Icon(Icons.check_circle, size: 14, color: scheme.primary),
              const SizedBox(width: Insets.xs),
            ],
            Expanded(
              child: Text(
                provider.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${provider.lang.toUpperCase()} · v${provider.version}'
          '${provider.nsfw ? ' · 18+' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        trailing: isInstalled
            ? TextButton(
                onPressed: onUninstall,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: const Text('Uninstall'),
              )
            : TextButton(onPressed: onInstall, child: const Text('Install')),
        onTap: isInstalled
            ? () => _showProviderInfo(
                context,
                provider,
                true,
                onInstall,
                onUninstall,
              )
            : onInstall,
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
  VoidCallback onInstall,
  VoidCallback onUninstall,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;

      return DraggableScrollableSheet(
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
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
            //
            // Labelled verbs, not a switch: this sheet is reachable from the
            // Catalog row, and which verb it offers depends on the state, so a
            // toggle would be a control whose meaning changes under the user.
            if (isInstalled)
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text('Uninstall', style: TextStyle(color: scheme.error)),
                subtitle: const Text('Remove from Browse and Search'),
                onTap: () {
                  Navigator.pop(context);
                  onUninstall();
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.download_done),
                title: const Text('Install'),
                subtitle: const Text('Adds it to Browse and Search'),
                onTap: () {
                  Navigator.pop(context);
                  onInstall();
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
      );
    },
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
