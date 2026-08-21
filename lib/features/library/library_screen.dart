import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/display_mode.dart';
import '../../core/providers/database_providers.dart';
import '../../core/utils/platform.dart';
import '../../theme/tokens.dart';
import '../../widgets/header_search_field.dart';
import '../../widgets/max_width_box.dart';
import '../../widgets/page_header.dart';
import '../../widgets/shimmer_list.dart';
import 'widgets/library_grid_item.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DisplayMode _displayMode = DisplayMode.grid;
  String _filterQuery = '';

  static const _tabs = [
    'All',
    'Reading',
    'On Hold',
    'Plan to Read',
    'Completed',
    'Dropped',
  ];

  static const _statusValues = [
    null,
    'Reading',
    'On Hold',
    'Plan to Read',
    'Completed',
    'Dropped',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return Scaffold(
        body: Column(
          children: [
            PageHeader(
              title: 'Library',
              search: HeaderSearchField(
                hint: 'Filter library',
                onChanged: (v) => setState(() => _filterQuery = v),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.file_upload),
                  onPressed: () => context.push('/import'),
                  tooltip: 'Import EPUB/PDF',
                ),
                IconButton(
                  icon: Icon(_displayMode.icon),
                  onPressed: () =>
                      setState(() => _displayMode = _displayMode.next),
                  tooltip: 'Display mode',
                ),
              ],
              tabController: _tabController,
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _tabs
                    .asMap()
                    .entries
                    .map((e) => _buildTabContent(e.key))
                    .toList(),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: () => context.push('/import'),
            tooltip: 'Import EPUB/PDF',
          ),
          IconButton(
            icon: Icon(_displayMode.icon),
            onPressed: () => setState(() => _displayMode = _displayMode.next),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs
            .asMap()
            .entries
            .map((e) => _buildTabContent(e.key))
            .toList(),
      ),
    );
  }

  Widget _buildTabContent(int tabIndex) {
    final libraryDao = ref.watch(libraryDaoProvider);
    final status = _statusValues[tabIndex];
    final stream = status == null
        ? libraryDao.watchLibraryNovels()
        : libraryDao.watchLibraryNovelsByStatus(status);

    return StreamBuilder<List<Novel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          switch (_displayMode) {
            case DisplayMode.grid:
              return const ShimmerGrid();
            case DisplayMode.list:
            case DisplayMode.compact:
              return const ShimmerList();
          }
        }

        final novels = snapshot.data ?? [];
        final query = _filterQuery.trim().toLowerCase();
        final filtered = query.isEmpty
            ? novels
            : novels
                  .where(
                    (n) =>
                        n.title.toLowerCase().contains(query) ||
                        (n.author?.toLowerCase().contains(query) ?? false),
                  )
                  .toList();

        if (filtered.isEmpty) {
          if (query.isNotEmpty && novels.isNotEmpty) {
            return Center(
              child: Text(
                'No results for "$_filterQuery"',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return Center(
            child: MaxWidthBox(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.xl,
                vertical: Insets.xxl,
              ),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.xxl,
                  vertical: Insets.xxxl,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: Radii.card,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.library_books,
                      size: 56,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: Insets.lg),
                    Text(
                      _tabs[tabIndex] == 'All'
                          ? 'No novels saved yet'
                          : 'No ${_tabs[tabIndex]} novels',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Insets.sm),
                    Text(
                      'Search for novels and add them\nto your library.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Insets.lg),
                    FilledButton.tonalIcon(
                      onPressed: () => context.go('/browse'),
                      icon: const Icon(Icons.explore, size: 18),
                      label: const Text('Browse sources'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        switch (_displayMode) {
          case DisplayMode.grid:
            // Full-bleed: left-aligns with the header at any window size;
            // wide windows get more columns instead of centering gutters.
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.lg,
                Insets.lg,
                Insets.xl,
              ),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                childAspectRatio: 0.68,
                crossAxisSpacing: Insets.md,
                mainAxisSpacing: Insets.md,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) => LibraryGridItem(
                novel: filtered[index],
                onTap: () => context.push('/novel/${filtered[index].id}'),
                onPlay: () => _playNovel(filtered[index].id),
                onLongPress: () => _showStatusMenu(filtered[index]),
              ),
            );
          case DisplayMode.list:
            return ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) => _buildListItem(filtered[index]),
            );
          case DisplayMode.compact:
            return ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) =>
                  _buildCompactItem(filtered[index]),
            );
        }
      },
    );
  }

  Widget _buildCover(String? url, double width, double height) {
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, _) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.book, size: 32),
        ),
        errorWidget: (_, _, _) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.book, size: 32),
        ),
      );
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.book, size: 32),
    );
  }

  Widget _buildListItem(Novel novel) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.all(Radii.sm),
        child: _buildCover(novel.coverUrl, 48, 64),
      ),
      title: Text(novel.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          novel.author,
          novel.status,
        ].where((s) => s != null && s.isNotEmpty).join(' · '),
        style: text.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_outline, size: 28),
        color: scheme.primary,
        onPressed: () => _playNovel(novel.id),
      ),
      onTap: () => context.push('/novel/${novel.id}'),
      onLongPress: () => _showStatusMenu(novel),
    );
  }

  Widget _buildCompactItem(Novel novel) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => context.push('/novel/${novel.id}'),
      onLongPress: () => _showStatusMenu(novel),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.all(Radii.sm),
              child: _buildCover(novel.coverUrl, 28, 38),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    novel.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                  if (novel.author != null && novel.author!.isNotEmpty)
                    Text(
                      novel.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (novel.status != null && novel.status!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.all(Radii.sm),
                ),
                child: Text(
                  novel.status!,
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _playNovel(int novelId) async {
    final chapterDao = ref.read(chapterDaoProvider);
    final historyDao = ref.read(historyDaoProvider);

    // Try to find the last read chapter
    final latest = await historyDao.getLatestHistoryForNovel(novelId);
    if (latest != null && mounted) {
      context.push('/reader/$novelId/${latest.chapterId}');
      return;
    }

    // Fallback: open first chapter
    final chapters = await chapterDao.getChaptersForNovel(novelId);
    if (chapters.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No chapters available')));
      }
      return;
    }
    if (mounted) {
      context.push('/reader/$novelId/${chapters.first.id}');
    }
  }

  void _showStatusMenu(Novel novel) {
    final libraryDao = ref.read(libraryDaoProvider);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              novel.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          for (final s in [
            'Reading',
            'On Hold',
            'Plan to Read',
            'Completed',
            'Dropped',
          ])
            ListTile(
              leading: const Icon(Icons.library_books),
              title: Text(s),
              onTap: () {
                libraryDao.updateStatus(novel.id, s);
                Navigator.pop(ctx);
              },
            ),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.remove_circle,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'None',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () {
              libraryDao.removeFromLibrary(novel.id);
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}
