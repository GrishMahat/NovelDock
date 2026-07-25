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
import '../../theme/app_theme.dart';
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

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final registry = await ref.read(registryManagerProvider.future);
      final engine = ref.read(providerEngineProvider);
      final jsSource = await registry.loadCachedProviderJs(item.providerId!);
      Log.i(_tag, '_openNovel: jsSource=${jsSource != null ? '${jsSource.length} chars' : 'null'}');
      if (jsSource != null) {
        final instance = await engine.loadProvider(jsSource);
        final novelUrl = await instance.getNovelInfoUrl(item.url);
        Log.i(_tag, '_openNovel: novelUrl=$novelUrl');
        if (novelUrl != null) {
          final dio = await ref.read(dioProvider.future);
          final response = await dio.get(novelUrl);
          final html = response.data.toString();
          Log.i(_tag, '_openNovel: fetched ${html.length} chars from $novelUrl');
          final info = await instance.parseNovelInfo(html);
          Log.i(_tag, '_openNovel: parsed info=${info != null ? 'title="${info.title}" chapters=${info.chapters.length}' : 'null'}');
          if (info != null && mounted) {
            Log.i(_tag, '_openNovel: updating novel id=$id description len=${info.description.length} genres=${info.genres} status=${info.status}');
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
            Log.i(_tag, '_openNovel: info.chapters=${info.chapters.length}, bookId=$bookId');
            // Delete existing chapters before re-inserting to prevent duplicates
            await chapterDao.deleteChaptersForNovel(id);
            if (info.chapters.isEmpty && bookId.isNotEmpty) {
              Log.i(_tag, '_openNovel: loading chapters via AJAX for bookId=$bookId');
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
                Log.i(_tag, '_openNovel: parsed ${chList.length} chapters from page $page');
                for (var i = 0; i < chList.length; i++) {
                  final ch = chList[i] as Map<String, dynamic>;
                  await chapterDao.insertChapter(ChaptersCompanion(
                    novelId: Value(id),
                    name: Value(ch['name'] as String? ?? ''),
                    url: Value(ch['url'] as String? ?? ''),
                    index: Value(chapterIndex.toDouble()),
                  ));
                  chapterIndex++;
                }
                page++;
              }
              Log.i(_tag, '_openNovel: done loading chapters, total=$chapterIndex');
            } else {
              for (var i = 0; i < info.chapters.length; i++) {
                final ch = info.chapters[i];
                await chapterDao.insertChapter(ChaptersCompanion(
                  novelId: Value(id),
                  name: Value(ch.name),
                  url: Value(ch.url),
                  index: Value(i.toDouble()),
                ));
              }
            }
            Log.i(_tag, '_openNovel: done inserting chapters');
          } else {
            Log.w(_tag, '_openNovel: info was null or not mounted');
          }
        } else {
          Log.e(_tag, '_openNovel: novelUrl returned null');
        }
      } else {
        Log.e(_tag, '_openNovel: no cached JS for provider ${item.providerId}');
      }
    } catch (e, stack) {
      Log.e(_tag, '_openNovel: error', e);
      Log.e(_tag, '_openNovel: stack', stack);
    }

    if (mounted) {
      // Dismiss loading dialog
      Navigator.of(context, rootNavigator: true).pop();
      Log.i(_tag, '_openNovel: navigating to /novel/$id');
      context.push('/novel/$id');
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
            : const Text('QuickNovel'),
        actions: [
          if (_currentQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchController.clear();
                setState(() => _currentQuery = '');
                ref.read(searchProvider.notifier).clear();
              },
            ),
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
      return const Center(child: CircularProgressIndicator());
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

    return ListView.builder(
      itemCount: searchState.results.length,
      itemBuilder: (context, index) {
        final item = searchState.results[index];
        return _buildSearchResultItem(item);
      },
    );
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
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  provider.name.isNotEmpty
                      ? provider.name[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
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
}
