import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../core/providers/engine.dart';
import '../../theme/app_theme.dart';
import 'providers/search_providers.dart';

class SearchResultsScreen extends ConsumerStatefulWidget {
  final String query;
  const SearchResultsScreen({super.key, required this.query});

  @override
  ConsumerState<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  late final PagingController<int, SearchResultItem> _pagingController;

  @override
  void initState() {
    super.initState();
    _pagingController = PagingController(
      getNextPageKey: (state) {
        if (state.pages?.last.isNotEmpty == true) {
          return (state.pages?.length ?? 0) + 1;
        }
        return null;
      },
      fetchPage: (pageKey) async {
        final searchState = ref.read(searchProvider.notifier);
        await searchState.search(widget.query, page: pageKey);
        return ref.read(searchProvider).results;
      },
    );
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Search: ${widget.query}'),
      ),
      body: PagingListener<int, SearchResultItem>(
        controller: _pagingController,
        builder: (context, state, fetchNextPage) {
          return PagedListView<int, SearchResultItem>(
            state: state,
            fetchNextPage: fetchNextPage,
            builderDelegate: PagedChildBuilderDelegate<SearchResultItem>(
              itemBuilder: (context, item, index) {
                return _buildSearchResultItem(item);
              },
              noItemsFoundIndicatorBuilder: (context) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: AppTheme.kTextSecondaryDark),
                      SizedBox(height: 16),
                      Text('No results found', style: TextStyle(fontSize: 18)),
                      SizedBox(height: 8),
                      Text(
                        'Try a different query or check your providers.',
                        style: TextStyle(color: AppTheme.kTextSecondaryDark),
                      ),
                    ],
                  ),
                );
              },
              firstPageProgressIndicatorBuilder: (context) {
                return const Center(child: CircularProgressIndicator());
              },
              newPageProgressIndicatorBuilder: (context) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              firstPageErrorIndicatorBuilder: (context) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text('Search failed'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => _pagingController.refresh(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResultItem(SearchResultItem item) {
    return ListTile(
      leading: item.cover != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                item.cover!,
                width: 48,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 48,
                  height: 64,
                  color: AppTheme.kSurfaceVariantDark,
                  child: const Icon(Icons.broken_image),
                ),
              ),
            )
          : Container(
              width: 48,
              height: 64,
              color: AppTheme.kSurfaceVariantDark,
              child: const Icon(Icons.book),
            ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (item.author != null) item.author!,
          if (item.latestChapter != null) 'Ch. ${item.latestChapter}',
        ].join(' · '),
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: item.rating != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, size: 14, color: Colors.amber),
                const SizedBox(width: 2),
                Text('${item.rating}', style: const TextStyle(fontSize: 12)),
              ],
            )
          : null,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening: ${item.title}')),
        );
      },
    );
  }
}
