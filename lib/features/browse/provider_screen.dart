import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../core/providers/engine.dart';
import '../../core/providers/filters.dart';
import '../../core/network/client.dart';
import '../../core/providers/novel_opener.dart';
import '../../core/utils/logger.dart';
import '../../widgets/novel_card.dart';
import '../search/providers/search_providers.dart';
import '../search/widgets/filter_sheet.dart';
import '../settings/providers/provider_management_providers.dart';

const _tag = 'ProviderScreen';

enum _ListMode { popular, latest, search }

class ProviderScreen extends ConsumerStatefulWidget {
  final String providerId;

  const ProviderScreen({super.key, required this.providerId});

  @override
  ConsumerState<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends ConsumerState<ProviderScreen>
    with SingleTickerProviderStateMixin {
  late final PagingController<int, SearchResultItem> _pagingController;
  late final TabController _tabController;
  bool _isGridView = true;
  bool _isSearching = false;
  ProviderInstance? _instance;
  bool _hasReachedEnd = false;
  static const _maxPages = 100;

  _ListMode _mode = _ListMode.popular;
  String _query = '';
  FilterValues _filters = const FilterValues();
  final _searchController = TextEditingController();

  bool get _canLatest => _instance?.flags.hasLatest ?? false;
  bool get _canFilter => _instance?.flags.hasFilters ?? false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      if (_mode == _ListMode.search) return;
      _setMode(_tabController.index == 1 ? _ListMode.latest : _ListMode.popular);
    });
    _pagingController = PagingController(
      getNextPageKey: (state) {
        if (_hasReachedEnd) return null;
        if (state.pages == null || state.pages!.isEmpty) return 1;
        if (state.pages!.last.isNotEmpty) {
          final nextPage = state.pages!.length + 1;
          if (nextPage > _maxPages) return null;
          return nextPage;
        }
        return null;
      },
      fetchPage: _fetchPage,
    );
    _ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pagingController.dispose();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<ProviderInstance?> _ensureLoaded() async {
    if (_instance == null) {
      _instance = await loadProviderById(widget.providerId, ref.container);
      if (_instance == null) {
        Log.e(_tag, 'No cached provider for ${widget.providerId}');
      }
    }
    return _instance;
  }

  Future<List<SearchResultItem>> _fetchPage(int pageKey) async {
    Log.i(_tag, 'Fetching page $pageKey for provider: ${widget.providerId} '
        '(mode: $_mode, query: "$_query")');

    try {
      final instance = await _ensureLoaded();
      if (instance == null) return [];

      final dio = await ref.read(dioProvider.future);

      String? url;
      switch (_mode) {
        case _ListMode.latest:
          url = await instance.getLatestUrl(pageKey);
        case _ListMode.search:
          Log.i(_tag, 'Search mode: hasFunction(getSearchConfig)='
              '${instance.hasFunction('getSearchConfig')}, '
              'exported=${instance.exportedFunctions.length} fns');
          if (instance.hasFunction('getSearchConfig')) {
            final results = await searchProviderOnce(
              instance,
              dio,
              _query,
              _filters,
              pageKey,
            );
            if (results != null) {
              if (!results.hasNextPage) _hasReachedEnd = true;
              Log.ok(_tag, 'Got ${results.results.length} results');
              return results.results
                  .map((e) => _toItem(e))
                  .toList();
            }
            Log.w(_tag, 'searchProviderOnce returned null/empty, '
                'falling back to GET search URL');
          }
          url = await instance.getSearchUrl(
            _query,
            pageKey,
            filters: _filters,
          );
          Log.i(_tag, 'GET fallback URL: $url');
        case _ListMode.popular:
          url = await instance.getMainPageUrl(pageKey, filters: _filters);
      }

      // Fallback for providers without a main page: empty search.
      if (url == null && _mode == _ListMode.popular) {
        url = await instance.getSearchUrl('', pageKey);
      }
      if (url == null) return [];

      Log.i(_tag, 'Fetching: $url');
      final response = await dio.get(url);
      final html = response.data.toString();

      final results = await instance.parseSearchResults(html);
      if (results != null) {
        if (!results.hasNextPage) _hasReachedEnd = true;
        Log.ok(_tag, 'Got ${results.results.length} results');
        return results.results
            .map((e) => _toItem(e))
            .toList();
      }

      Log.w(_tag, 'No results found');
      return [];
    } catch (e) {
      Log.e(_tag, 'Error fetching page', e);
      return [];
    }
  }

  SearchResultItem _toItem(SearchResultItem e) {
    return SearchResultItem(
      title: e.title,
      url: e.url,
      cover: e.cover,
      author: e.author,
      summary: e.summary,
      rating: e.rating,
      latestChapter: e.latestChapter,
      providerId: widget.providerId,
      coverHeaders: e.coverHeaders,
    );
  }

  Future<void> _openNovel(SearchResultItem item) async {
    if (item.providerId == null) return;
    final id = await NovelOpener(ref).open(item);
    if (!mounted || id <= 0) return;
    context.push('/novel/$id');
  }

  void _setMode(_ListMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    _hasReachedEnd = false;
    _pagingController.refresh();
  }

  void _submitSearch(String q) {
    final query = q.trim();
    setState(() => _query = query);
    if (query.isEmpty) {
      _setMode(
        _tabController.index == 1 ? _ListMode.latest : _ListMode.popular,
      );
      return;
    }
    _setMode(_ListMode.search);
  }

  Future<void> _openFilterSheet() async {
    final instance = await _ensureLoaded();
    if (instance == null || !instance.flags.hasFilters) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This source has no filters')),
        );
      }
      return;
    }
    final defs = await instance.getFilters();
    if (defs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This source has no filters')),
        );
      }
      return;
    }
    if (!mounted) return;
    final applied = await FilterSheet.show(
      context,
      defs: defs,
      initial: _filters,
      onApply: (values) async {},
    );
    if (applied != null) {
      setState(() => _filters = applied);
      _hasReachedEnd = false;
      _pagingController.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(availableProvidersProvider);
    final title = providersAsync.value
            ?.where((p) => p.id == widget.providerId)
            .firstOrNull
            ?.name ??
        widget.providerId;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search in this source...',
                  border: InputBorder.none,
                ),
                onSubmitted: _submitSearch,
              )
            : Text(title),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search in this source',
              onPressed: () => setState(() => _isSearching = true),
            )
          else
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close search',
              onPressed: () => setState(() => _isSearching = false),
            ),
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            tooltip: 'Display mode',
            iconSize: 26,
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_canLatest || _canFilter)
            Row(
              children: [
                if (_canLatest)
                  Expanded(
                    child: IgnorePointer(
                      ignoring: _mode == _ListMode.search,
                      child: TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: 'Popular'),
                          Tab(text: 'Latest'),
                        ],
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 12),
                if (_canFilter)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.filter_list),
                      tooltip: 'Filters',
                      iconSize: 24,
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: _openFilterSheet,
                    ),
                  ),
              ],
            ),
          Expanded(
            child: _instance == null
                ? const Center(child: CircularProgressIndicator())
                : PagingListener<int, SearchResultItem>(
                    controller: _pagingController,
                    builder: (context, state, fetchNextPage) {
                      if (_isGridView) {
                        return PagedGridView<int, SearchResultItem>(
                          state: state,
                          fetchNextPage: fetchNextPage,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.68,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          padding: const EdgeInsets.all(8),
                          builderDelegate: PagedChildBuilderDelegate<
                              SearchResultItem>(
                            itemBuilder: (context, item, index) =>
                                _buildGridItem(item),
                            noItemsFoundIndicatorBuilder: (context) => Center(
                              child: Text(
                                _mode == _ListMode.search
                                    ? 'No results for "$_query"'
                                    : 'No items found',
                              ),
                            ),
                            firstPageProgressIndicatorBuilder: (context) =>
                                const Center(
                              child: CircularProgressIndicator(),
                            ),
                            newPageProgressIndicatorBuilder: (context) =>
                                const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                        );
                      }
                      return PagedListView<int, SearchResultItem>(
                        state: state,
                        fetchNextPage: fetchNextPage,
                        builderDelegate: PagedChildBuilderDelegate<
                            SearchResultItem>(
                          itemBuilder: (context, item, index) =>
                              _buildListItem(item),
                          noItemsFoundIndicatorBuilder: (context) => Center(
                            child: Text(
                              _mode == _ListMode.search
                                  ? 'No results for "$_query"'
                                  : 'No items found',
                            ),
                          ),
                          firstPageProgressIndicatorBuilder: (context) =>
                              const Center(child: CircularProgressIndicator()),
                          newPageProgressIndicatorBuilder: (context) =>
                              const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(SearchResultItem item) {
    return NovelGridCard(item: item, onTap: () => _openNovel(item));
  }

  Widget _buildListItem(SearchResultItem item) {
    return NovelListTile(item: item, onTap: () => _openNovel(item));
  }
}