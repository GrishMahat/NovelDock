import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../core/providers/engine.dart';
import '../../core/network/client.dart';
import '../../core/utils/logger.dart';
import '../../core/providers/database_providers.dart';
import '../../core/database/database.dart';
import '../../theme/app_theme.dart';

const _tag = 'ProviderScreen';

class ProviderScreen extends ConsumerStatefulWidget {
  final String providerId;
  const ProviderScreen({super.key, required this.providerId});

  @override
  ConsumerState<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends ConsumerState<ProviderScreen> {
  late final PagingController<int, SearchResultItem> _pagingController;
  bool _isGridView = true;
  ProviderInstance? _instance;
  bool _hasReachedEnd = false;
  static const _maxPages = 100;

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  Future<List<SearchResultItem>> _fetchPage(int pageKey) async {
    Log.i(_tag, 'Fetching page $pageKey for provider: ${widget.providerId}');

    try {
      // Use cached provider instance
      if (_instance == null) {
        _instance = await loadProviderById(widget.providerId, ref);
        if (_instance == null) {
          Log.e(_tag, 'No cached provider for ${widget.providerId}');
          return [];
        }
        Log.ok(_tag, 'Provider loaded');
      }

      // Try to get main page URL
      final mainUrl = await _instance!.call('getMainPageUrl', [pageKey]);
      if (mainUrl != null && mainUrl is String) {
        Log.i(_tag, 'Fetching main page: $mainUrl');
        final dio = await ref.read(dioProvider.future);
        final response = await dio.get(mainUrl);
        final html = response.data.toString();
        Log.i(_tag, 'Got ${html.length} chars of HTML');

        final results = await _instance!.parseSearchResults(html);
        if (results != null) {
          if (!results.hasNextPage) _hasReachedEnd = true;
          Log.ok(_tag, 'Got ${results.results.length} results');
          return results.results
              .map((e) => SearchResultItem(
                    title: e.title,
                    url: e.url,
                    cover: e.cover,
                    author: e.author,
                    summary: e.summary,
                    rating: e.rating,
                    latestChapter: e.latestChapter,
                    providerId: widget.providerId,
                    coverHeaders: e.coverHeaders,
                  ))
              .toList();
        }
      }

      // Fallback: try search with empty query
      Log.i(_tag, 'Trying empty search...');
      final searchUrl = await _instance!.getSearchUrl('', pageKey);
      if (searchUrl != null) {
        Log.i(_tag, 'Fetching: $searchUrl');
        final dio = await ref.read(dioProvider.future);
        final response = await dio.get(searchUrl);
        final html = response.data.toString();
        Log.i(_tag, 'Got ${html.length} chars of HTML');

        final results = await _instance!.parseSearchResults(html);
        if (results != null) {
          if (!results.hasNextPage) _hasReachedEnd = true;
          Log.ok(_tag, 'Got ${results.results.length} results');
          return results.results
              .map((e) => SearchResultItem(
                    title: e.title,
                    url: e.url,
                    cover: e.cover,
                    author: e.author,
                    summary: e.summary,
                    rating: e.rating,
                    latestChapter: e.latestChapter,
                    providerId: widget.providerId,
                    coverHeaders: e.coverHeaders,
                  ))
              .toList();
        }
      }

      Log.w(_tag, 'No results found');
      return [];
    } catch (e) {
      Log.e(_tag, 'Error fetching page', e);
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.providerId),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
          ),
        ],
      ),
      body: PagingListener<int, SearchResultItem>(
        controller: _pagingController,
        builder: (context, state, fetchNextPage) {
          if (_isGridView) {
            return PagedGridView<int, SearchResultItem>(
              state: state,
              fetchNextPage: fetchNextPage,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.68,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              padding: const EdgeInsets.all(8),
              builderDelegate: PagedChildBuilderDelegate<SearchResultItem>(
                itemBuilder: (context, item, index) => _buildGridItem(item),
                noItemsFoundIndicatorBuilder: (context) => const Center(
                  child: Text('No items found'),
                ),
                firstPageProgressIndicatorBuilder: (context) =>
                    const Center(child: CircularProgressIndicator()),
              ),
            );
          } else {
            return PagedListView<int, SearchResultItem>(
              state: state,
              fetchNextPage: fetchNextPage,
              builderDelegate: PagedChildBuilderDelegate<SearchResultItem>(
                itemBuilder: (context, item, index) => _buildListItem(item),
                noItemsFoundIndicatorBuilder: (context) =>
                    const Center(child: Text('No items found')),
                firstPageProgressIndicatorBuilder: (context) =>
                    const Center(child: CircularProgressIndicator()),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _openNovel(SearchResultItem item) async {
    if (item.providerId == null) return;
    final novelDao = ref.read(novelDaoProvider);
    final chapterDao = ref.read(chapterDaoProvider);
    final id = await novelDao.insertOrGetNovel(
      providerId: item.providerId!,
      url: item.url,
      title: item.title,
      author: item.author,
      coverUrl: item.cover,
    );
    if (!mounted) return;

    // Navigate immediately with local data
    context.push('/novel/$id');

    // Fetch novel details and chapters in the background
    _fetchNovelDetails(id, item);
  }

  Future<void> _fetchNovelDetails(int id, SearchResultItem item) async {
    if (!mounted) return;
    try {
      final instance = await loadProviderById(item.providerId!, ref);
      if (instance != null) {
        final novelDao = ref.read(novelDaoProvider);
        final chapterDao = ref.read(chapterDaoProvider);

        final novelUrl = await instance.getNovelInfoUrl(item.url);
        if (novelUrl != null) {
          final dio = await ref.read(dioProvider.future);
          final response = await dio.get(novelUrl);
          final info = await instance.parseNovelInfo(response.data.toString());
          if (info != null && mounted) {
            novelDao.updateNovel(NovelsCompanion(
              id: Value(id),
              providerId: Value(item.providerId!),
              url: Value(item.url),
              title: Value(item.title),
              author: Value(item.author ?? info.author),
              coverUrl: Value(item.cover ?? info.cover),
              description: Value(info.description),
              genres: Value(info.genres.join(',')),
              status: Value(info.status),
              addedAt: Value(DateTime.now().millisecondsSinceEpoch),
            ));
            final bookId = item.url.split('/').last.split('.').first;
            final chapterList = <ChaptersCompanion>[];
            if (info.chapters.isEmpty && bookId.isNotEmpty) {
              var page = 0;
              var chapterIndex = 0;
              while (true) {
                final chaptersUrl = await instance.call('getChaptersApiUrl', [bookId, page]);
                if (chaptersUrl == null || chaptersUrl is! String) break;
                final chResponse = await dio.get(chaptersUrl);
                final chHtml = chResponse.data.toString();
                if (chHtml.trim().isEmpty) break;
                final chList = await instance.call('parseChapterList', [chHtml]);
                if (chList == null || chList is! List || chList.isEmpty) break;
                for (var i = 0; i < chList.length; i++) {
                  final ch = chList[i] as Map<String, dynamic>;
                  chapterList.add(ChaptersCompanion(
                    novelId: Value(id),
                    name: Value(ch['name'] as String? ?? ''),
                    url: Value(ch['url'] as String? ?? ''),
                    index: Value(chapterIndex.toDouble()),
                  ));
                  chapterIndex++;
                }
                page++;
              }
            } else {
              for (var i = 0; i < info.chapters.length; i++) {
                final ch = info.chapters[i];
                chapterList.add(ChaptersCompanion(
                  novelId: Value(id),
                  name: Value(ch.name),
                  url: Value(ch.url),
                  index: Value(i.toDouble()),
                ));
              }
            }
            await chapterDao.insertChaptersForNovel(id, chapterList);
          }
        }
      }
    } catch (_) {}
  }

  Widget _buildGridItem(SearchResultItem item) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openNovel(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: item.cover != null
                  ? Image.network(
                      item.cover!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: AppTheme.kSurfaceVariantDark,
                        child: const Icon(Icons.broken_image),
                      ),
                    )
                  : Container(
                      color: AppTheme.kSurfaceVariantDark,
                      child: const Icon(Icons.book, size: 32),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                item.title,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(SearchResultItem item) {
    return ListTile(
      leading: item.cover != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                item.cover!,
                width: 48,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
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
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        item.author ?? '',
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
      ),
      onTap: () => _openNovel(item),
    );
  }
}
