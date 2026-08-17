import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/engine.dart';
import '../../core/providers/models.dart';
import '../../core/providers/novel_opener.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/novel_card.dart';
import '../../widgets/provider_avatar.dart';
import '../settings/providers/provider_management_providers.dart';
import 'providers/search_providers.dart';
import 'widgets/filter_sheet.dart';

/// Global search results — one horizontal row per source.
///
/// Tapping a row header opens that source's complete loaded result set in a
/// bottom sheet.
class SearchResultsScreen extends ConsumerStatefulWidget {
  final String query;

  const SearchResultsScreen({super.key, required this.query});

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController(text: widget.query);

    Future.microtask(() {
      if (!mounted) return;

      ref.read(searchProvider.notifier).search(widget.query);
    });
  }

  @override
  void didUpdateWidget(covariant SearchResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.query != widget.query) {
      _searchController.text = widget.query;

      Future.microtask(() {
        if (!mounted) return;

        ref.read(searchProvider.notifier).search(widget.query);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearch(String query) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) return;

    if (_searchController.text != trimmed) {
      _searchController.value = TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
    }

    await ref.read(searchProvider.notifier).search(trimmed);
  }

  Future<void> _openNovel(SearchResultItem item) async {
    if (item.providerId == null) return;

    final id = await NovelOpener(ref).open(item);

    if (!mounted || id <= 0) return;

    context.push('/novel/$id');
  }

  Future<void> _openSourceSheet(
    List<ProviderMeta> providers,
    Set<String> selected,
  ) async {
    await SearchSourcesSheet.show(
      context,
      providers: [
        for (final provider in providers) MapEntry(provider.id, provider.name),
      ],
      selected: selected,
      onChanged: (selection) {
        ref.read(searchProviderSelectionProvider.notifier).setAll(selection);

        // Fire-and-forget is intentional here. The notifier owns the
        // async search lifecycle and the screen remains responsive.
        ref.read(searchProvider.notifier).refreshSelection();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(availableProvidersProvider);
    final enabled = ref.watch(enabledProvidersProvider);
    final searchState = ref.watch(searchProvider);

    final providers =
        providersAsync.value
            ?.where((provider) => enabled.contains(provider.id))
            .toList(growable: false) ??
        const <ProviderMeta>[];

    final selectionNotifier = ref.watch(
      searchProviderSelectionProvider.notifier,
    );

    final selected = selectionNotifier.effective(enabled);

    final rowProviders = providers
        .where((provider) => selected.contains(provider.id))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'Search novels...',
            border: InputBorder.none,
          ),
          onSubmitted: _onSearch,
        ),
        actions: [
          if (searchState.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Search sources',
              onPressed: providersAsync.isLoading
                  ? null
                  : () => _openSourceSheet(providers, selected),
            ),
        ],
      ),
      body: _SearchRows(
        providers: rowProviders,
        allEnabledProviders: providers,
        onOpen: _openNovel,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Search rows
// ═══════════════════════════════════════════════════════════

class _SearchRows extends ConsumerWidget {
  final List<ProviderMeta> providers;
  final List<ProviderMeta> allEnabledProviders;
  final void Function(SearchResultItem) onOpen;

  const _SearchRows({
    required this.providers,
    required this.allEnabledProviders,
    required this.onOpen,
  });

  Future<void> _retryAll(
    BuildContext context,
    WidgetRef ref,
    String query,
  ) async {
    if (query.isEmpty) return;

    await ref.read(searchProvider.notifier).search(query);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchProvider);

    final selectedIds = searchState.selectedProviders;

    // Prefer the state captured by the current search, rather than relying
    // only on the current provider-selection settings. This prevents the UI
    // from displaying a row for a provider that is no longer part of the
    // active search.
    final activeProviders = allEnabledProviders
        .where((provider) => selectedIds.contains(provider.id))
        .toList(growable: false);

    if (activeProviders.isEmpty) {
      return const Center(
        child: Text(
          'No sources selected.\nTap the tune icon to pick sources.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.kTextSecondaryDark),
        ),
      );
    }

    final hasLoadingProviders = activeProviders.any(
      (provider) => searchState.stateFor(provider.id).isLoading,
    );

    final visible = activeProviders
        .where((provider) => searchState.stateFor(provider.id).loaded)
        .toList(growable: false);

    final hasAnyResults = activeProviders.any(
      (provider) => searchState.stateFor(provider.id).results.isNotEmpty,
    );

    final allCompleted = activeProviders.every((provider) {
      final state = searchState.stateFor(provider.id);
      return state.loaded && !state.isLoading;
    });

    final allFailed = activeProviders.every((provider) {
      final state = searchState.stateFor(provider.id);
      return !state.isLoading && state.error != null;
    });

    if (!hasAnyResults && hasLoadingProviders) {
      return const Center(child: CircularProgressIndicator());
    }

    if (allFailed && !hasAnyResults) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Search failed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'None of the selected sources returned results.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.kTextSecondaryDark),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: searchState.query.isEmpty
                    ? null
                    : () => _retryAll(context, ref, searchState.query),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Once every active provider has completed and none returned anything,
    // this really is the "no results" state.
    if (allCompleted && visible.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: AppTheme.kTextSecondaryDark,
              ),
              SizedBox(height: 16),
              Text('No results found', style: TextStyle(fontSize: 18)),
              SizedBox(height: 8),
              Text(
                'Try a different query.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.kTextSecondaryDark),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final provider in visible)
          _ProviderRow(
            provider: provider,
            state: searchState.stateFor(provider.id),
            onOpen: onOpen,
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Provider row
// ═══════════════════════════════════════════════════════════

class _ProviderRow extends ConsumerWidget {
  static const _previewCount = 8;

  final ProviderMeta provider;
  final ProviderSearchState state;
  final void Function(SearchResultItem) onOpen;

  const _ProviderRow({
    required this.provider,
    required this.state,
    required this.onOpen,
  });

  void _showFullList(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.4,
          maxChildSize: 1,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                  child: Row(
                    children: [
                      ProviderAvatar(provider: provider, radius: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${provider.name} • '
                          '${state.results.length} loaded',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: state.error != null && state.results.isEmpty
                      ? _ErrorContent(
                          onRetry: () => ref
                              .read(searchProvider.notifier)
                              .retryProvider(provider.id),
                        )
                      : _ProviderGrid(
                          state: state,
                          scrollController: scrollController,
                          onOpen: onOpen,
                          onLoadMore: () => ref
                              .read(searchProvider.notifier)
                              .loadMore(provider.id),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = state.results.take(_previewCount).toList(growable: false);

    final hasMorePreview =
        state.results.length > _previewCount || state.hasNextPage;

    final providerState = ref.watch(searchProvider).stateFor(provider.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _showFullList(context, ref),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
            child: Row(
              children: [
                ProviderAvatar(provider: provider, radius: 15),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    provider.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (providerState.error != null &&
                    providerState.results.isEmpty)
                  IconButton(
                    tooltip: 'Retry',
                    icon: const Icon(
                      Icons.refresh,
                      size: 20,
                      color: Colors.redAccent,
                    ),
                    onPressed: () => ref
                        .read(searchProvider.notifier)
                        .retryProvider(provider.id),
                  )
                else if (providerState.results.isEmpty &&
                    providerState.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (providerState.results.isEmpty)
                  const Text(
                    'No results',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.kTextSecondaryDark,
                    ),
                  )
                else
                  Text(
                    '${providerState.results.length}'
                    '${providerState.hasNextPage ? '+' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.kTextSecondaryDark,
                    ),
                  ),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
        if (preview.isNotEmpty)
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: preview.length + (hasMorePreview ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index >= preview.length) {
                  return SizedBox(
                    width: 112,
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: () => _showFullList(context, ref),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('View all'),
                      ),
                    ),
                  );
                }

                final item = preview[index];

                return SizedBox(
                  width: 112,
                  child: InkWell(
                    onTap: () => onOpen(item),
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CoverImage(
                            imageUrl: item.cover,
                            width: 112,
                            height: 152,
                            imageHeaders: item.coverHeaders,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        else if (providerState.isLoading)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (providerState.error == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'No results',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.kTextSecondaryDark,
              ),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Provider result grid
// ═══════════════════════════════════════════════════════════

class _ProviderGrid extends StatelessWidget {
  final ProviderSearchState state;
  final ScrollController scrollController;
  final VoidCallback onLoadMore;
  final void Function(SearchResultItem) onOpen;

  const _ProviderGrid({
    required this.state,
    required this.scrollController,
    required this.onLoadMore,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = state.results.length + (state.hasNextPage ? 1 : 0);

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisExtent: 235,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= state.results.length) {
          return Center(
            child: state.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : OutlinedButton.icon(
                    onPressed: onLoadMore,
                    icon: const Icon(Icons.expand_more, size: 18),
                    label: const Text('Load more'),
                  ),
          );
        }

        final item = state.results[index];

        return NovelGridCard(item: item, onTap: () => onOpen(item));
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Error content
// ═══════════════════════════════════════════════════════════

class _ErrorContent extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorContent({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              'Could not load results',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
