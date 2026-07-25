import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../theme/app_theme.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isGrid = true;

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
            icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGrid = !_isGrid),
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
        children: _tabs.asMap().entries.map((e) => _buildTabContent(e.key)).toList(),
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
          return const Center(child: CircularProgressIndicator());
        }

        final novels = snapshot.data ?? [];

        if (novels.isEmpty) {
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
                Text(
                  _tabs[tabIndex] == 'All'
                      ? 'No novels saved yet'
                      : 'No ${_tabs[tabIndex]} novels',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Search for novels and add them\nto your library.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.kTextSecondaryDark,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }

        if (_isGrid) {
          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.68,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: novels.length,
            itemBuilder: (context, index) => _buildGridItem(novels[index]),
          );
        } else {
          return ListView.builder(
            itemCount: novels.length,
            itemBuilder: (context, index) => _buildListItem(novels[index]),
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
        placeholder: (_, __) => Container(
          color: AppTheme.kSurfaceVariantDark,
          child: const Icon(Icons.book, size: 32),
        ),
        errorWidget: (_, __, ___) => Container(
          color: AppTheme.kSurfaceVariantDark,
          child: const Icon(Icons.book, size: 32),
        ),
      );
    }
    return Container(
      color: AppTheme.kSurfaceVariantDark,
      child: const Icon(Icons.book, size: 32),
    );
  }

  Widget _buildGridItem(Novel novel) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/novel/${novel.id}'),
        onLongPress: () => _showStatusMenu(novel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(novel.coverUrl, double.infinity, double.infinity),
                  // Play button overlay (bottom-right corner)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: GestureDetector(
                      onTap: () => _playNovel(novel.id),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.kPrimary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                novel.title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(Novel novel) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: _buildCover(novel.coverUrl, 48, 64),
      ),
      title: Text(novel.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [novel.author, novel.status].where((s) => s != null && s.isNotEmpty).join(' · '),
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_outline, size: 28),
        color: AppTheme.kPrimary,
        onPressed: () => _playNovel(novel.id),
      ),
      onTap: () => context.push('/novel/${novel.id}'),
      onLongPress: () => _showStatusMenu(novel),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No chapters available')),
        );
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
            child: Text(novel.title,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          for (final s in ['Reading', 'On Hold', 'Plan to Read', 'Completed', 'Dropped'])
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
            leading: Icon(Icons.remove_circle, color: Colors.red.shade400),
            title: Text('None', style: TextStyle(color: Colors.red.shade400)),
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
