import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/models.dart';
import '../../core/providers/engine.dart';
import '../../core/providers/registry.dart';
import '../../core/utils/logger.dart';
import '../../core/providers/database_providers.dart';
import '../../core/network/client.dart';
import '../../core/database/database.dart';
import '../../core/display_mode.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shimmer_list.dart';
import '../settings/providers/provider_management_providers.dart';
import '../search/providers/search_providers.dart';

const _tag = 'Home';

/// Home screen — the Search/Browse tab.
/// Shows a grid of enabled providers (pre-query) and search results (post-query).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String _currentQuery = '';
  DisplayMode _displayMode = DisplayMode.list;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openNovel(SearchResultItem item) async {
    Log.i(_tag, '_openNovel: title="${item.title}" url="${item.url}" providerId="${item.providerId}"');
    if (item.providerId == null) {
      Log.e(_tag, '_openNovel: providerId is null, aborting');
      return;
    }
    final novelDao = ref.read(novelDaoProvider);
    final chapterDao = ref.read(chapterDaoProvider);
    final id = await novelDao.insertOrGetNovel(
      providerId: item.providerId!,
      url: item.url,
      title: item.title,
      author: item.author,
      coverUrl: item.cover,
    );
    Log.i(_tag, '_openNovel: inserted/got novel DB id=$id');
    if (!mounted) return;

    // Navigate immediately with local data
    Log.i(_tag, '_openNovel: navigating to /novel/$id');
    context.push('/novel/$id');

    // Fetch novel details and chapters in the background
    _fetchNovelDetails(id, item);
  }

  Future<void> _fetchNovelDetails(int id, SearchResultItem item) async {
    if (!mounted) return;
    Log.i(_tag, '_fetchNovelDetails: id=$id');

    try {
      final instance = await loadProviderById(item.providerId!, ref);
      Log.i(_tag, '_fetchNovelDetails: instance=${instance != null ? 'loaded' : 'null'}');
      if (instance != null) {
        final novelDao = ref.read(novelDaoProvider);
        final chapterDao = ref.read(chapterDaoProvider);

        final novelUrl = await instance.getNovelInfoUrl(item.url);
        Log.i(_tag, '_fetchNovelDetails: novelUrl=$novelUrl');
        if (novelUrl != null) {
          final dio = await ref.read(dioProvider.future);
          final response = await dio.get(novelUrl);
          final html = response.data.toString();
          Log.i(_tag, '_fetchNovelDetails: fetched ${html.length} chars from $novelUrl');
          final info = await instance.parseNovelInfo(html);
          Log.i(_tag, '_fetchNovelDetails: parsed info=${info != null ? 'title="${info.title}" chapters=${info.chapters.length}' : 'null'}');
          if (info != null && mounted) {
            Log.i(_tag, '_fetchNovelDetails: updating novel id=$id description len=${info.description.length} genres=${info.genres} status=${info.status}');
            await novelDao.updateNovel(NovelsCompanion(
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
            Log.i(_tag, '_fetchNovelDetails: info.chapters=${info.chapters.length}, bookId=$bookId');
            final chapterList = <ChaptersCompanion>[];
            if (info.chapters.isEmpty && bookId.isNotEmpty) {
              Log.i(_tag, '_fetchNovelDetails: loading chapters via AJAX for bookId=$bookId');
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
                Log.i(_tag, '_fetchNovelDetails: parsed ${chList.length} chapters from page $page');
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
              Log.i(_tag, '_fetchNovelDetails: done loading chapters, total=$chapterIndex');
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
            Log.i(_tag, '_fetchNovelDetails: done inserting chapters');
          } else {
            Log.w(_tag, '_fetchNovelDetails: info was null or not mounted');
          }
        } else {
          Log.e(_tag, '_fetchNovelDetails: novelUrl returned null');
        }
      } else {
        Log.e(_tag, '_fetchNovelDetails: no cached JS for provider ${item.providerId}');
      }
    } catch (e, stack) {
      Log.e(_tag, '_fetchNovelDetails: error', e);
      Log.e(_tag, '_fetchNovelDetails: stack', stack);
    }
  }

  void _onSearch(String query) {
    if (query.trim().isEmpty) return;
    Log.i(_tag, 'Search triggered: "$query"');
    setState(() => _currentQuery = query.trim());
    ref.read(searchProvider.notifier).search(query.trim());
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(availableProvidersProvider);
    final enabledProviders = ref.watch(enabledProvidersProvider);
    final searchState = ref.watch(searchProvider);

    Log.d(_tag, 'Building: query="$_currentQuery", enabled=$enabledProviders');

    return Scaffold(
      appBar: AppBar(
        title: _currentQuery.isNotEmpty
            ? Text('Search: $_currentQuery')
            : const Text('NovelDock'),
        actions: [
          if (_currentQuery.isNotEmpty) ...[
            IconButton(
              icon: Icon(_displayMode.icon),
              onPressed: () => setState(() => _displayMode = _displayMode.next),
              tooltip: 'Display mode',
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchController.clear();
                setState(() => _currentQuery = '');
                ref.read(searchProvider.notifier).clear();
              },
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search novels...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: () => _onSearch(_searchController.text),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _onSearch,
            ),
          ),

          // Content
          Expanded(
            child: _currentQuery.isEmpty
                ? _buildProviderGrid(providersAsync, enabledProviders)
                : _buildSearchResults(searchState),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderGrid(
    AsyncValue<List<ProviderMeta>> providersAsync,
    Set<String> enabledProviders,
  ) {
    return providersAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: ShimmerGrid(crossAxisCount: 3, aspectRatio: 0.85),
      ),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (providers) {
        final enabled =
            providers.where((p) => enabledProviders.contains(p.id)).toList();

        Log.d(_tag, 'Provider grid: ${providers.length} total, ${enabled.length} enabled');

        if (enabled.isEmpty) {
          return _buildEmptyState();
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.85,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: enabled.length,
          itemBuilder: (context, index) {
            return _buildProviderCard(enabled[index]);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books,
            size: 64,
            color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No providers enabled',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Go to Settings > Providers to\nenable providers for browsing.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.kTextSecondaryDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(SearchState searchState) {
    if (searchState.isLoading) {
      return const ShimmerList();
    }

    if (searchState.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Search failed: ${searchState.error}'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(searchProvider.notifier).search(_currentQuery),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (searchState.results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: AppTheme.kTextSecondaryDark),
            SizedBox(height: 16),
            Text('No results found', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }

    switch (_displayMode) {
      case DisplayMode.grid:
        return GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.68,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: searchState.results.length,
          itemBuilder: (context, index) => _buildSearchGridItem(searchState.results[index]),
        );
      case DisplayMode.list:
        return ListView.builder(
          itemCount: searchState.results.length,
          itemBuilder: (context, index) {
            final item = searchState.results[index];
            return _buildSearchResultItem(item);
          },
        );
      case DisplayMode.compact:
        return ListView.builder(
          itemCount: searchState.results.length,
          itemBuilder: (context, index) {
            final item = searchState.results[index];
            return _buildSearchCompactItem(item);
          },
        );
    }
  }

  Widget _buildProviderCard(ProviderMeta provider) {
    final color = Color(
      provider.name.hashCode.toUnsigned(32) | 0xFF000000,
    ).withValues(alpha: 0.7);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/provider/${provider.id}'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildProviderIcon(provider, color),
            const SizedBox(height: 8),
            Text(
              provider.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderIcon(ProviderMeta provider, Color color) {
    return FutureBuilder<File?>(
      future: _getIconFile(provider.id),
      builder: (context, snapshot) {
        final iconFile = snapshot.data;

        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: iconFile != null ? Colors.transparent : color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: iconFile != null
              ? Image.file(
                  iconFile,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _letterAvatar(provider, color),
                )
              : _letterAvatar(provider, color),
        );
      },
    );
  }

  Future<File?> _getIconFile(String providerId) async {
    final registry = await ref.read(registryManagerProvider.future);
    return registry.loadCachedProviderIcon(providerId);
  }

  Widget _letterAvatar(ProviderMeta provider, Color color) {
    return Center(
      child: Text(
        provider.name.isNotEmpty ? provider.name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: color,
        ),
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
      onTap: () => _openNovel(item),
    );
  }

  Widget _buildSearchGridItem(SearchResultItem item) {
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
                      child: const Icon(Icons.book),
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

  Widget _buildSearchCompactItem(SearchResultItem item) {
    return InkWell(
      onTap: () => _openNovel(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: item.cover != null
                  ? Image.network(
                      item.cover!,
                      width: 28,
                      height: 38,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 28,
                        height: 38,
                        color: AppTheme.kSurfaceVariantDark,
                        child: const Icon(Icons.broken_image, size: 16),
                      ),
                    )
                  : Container(
                      width: 28,
                      height: 38,
                      color: AppTheme.kSurfaceVariantDark,
                      child: const Icon(Icons.book, size: 16),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (item.author != null)
                    Text(
                      item.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppTheme.kTextSecondaryDark),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
