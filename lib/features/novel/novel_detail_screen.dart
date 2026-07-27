import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../core/utils/logger.dart';
import '../../core/network/cloudflare.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shimmer_list.dart';
import '../downloads/providers/download_provider.dart';
import 'widgets/status_picker_sheet.dart';
import 'widgets/download_range_sheet.dart';

/// Novel detail screen — shows novel info with tabs: Novel, Reviews, Related, Chapters.
class NovelDetailScreen extends ConsumerStatefulWidget {
  final int novelId;
  const NovelDetailScreen({super.key, required this.novelId});

  @override
  ConsumerState<NovelDetailScreen> createState() => _NovelDetailScreenState();
}

class _NovelDetailScreenState extends ConsumerState<NovelDetailScreen> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  Novel? _novel;
  bool _novelLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadNovel();
  }

  Future<void> _loadNovel() async {
    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(widget.novelId);
    if (mounted) {
      setState(() {
        _novel = novel;
        _novelLoaded = true;
      });
    }
  }

  void _showDownloadDialog(BuildContext context, WidgetRef ref) {
    final chapterDao = ref.read(chapterDaoProvider);

    chapterDao.getChaptersForNovel(widget.novelId).then((chapters) {
      if (!context.mounted) return;

      if (chapters.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No chapters to download')),
        );
        return;
      }

      final minChapter = chapters.first.index;
      final maxChapter = chapters.last.index;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => DownloadRangeSheet(
          totalChapters: chapters.length,
          minChapter: minChapter,
          maxChapter: maxChapter,
          onDownloadAll: () {
            Navigator.pop(ctx);
            ref.read(downloadProvider.notifier).downloadAllChapters(widget.novelId);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Downloading ${chapters.length} chapters')),
            );
          },
          onDownloadRange: (start, end) {
            Navigator.pop(ctx);
            ref.read(downloadProvider.notifier).downloadChapterRange(widget.novelId, start.round(), end.round());
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Downloading chapters $start-$end')),
            );
          },
        ),
      );
    });
  }

  void _playFromStart(WidgetRef ref) async {
    final chapterDao = ref.read(chapterDaoProvider);
    final chapters = await chapterDao.getChaptersForNovel(widget.novelId);
    if (chapters.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No chapters to play')),
        );
      }
      return;
    }
    // Open the first chapter in reader — TTS will start from there
    if (mounted) {
      context.push('/reader/${widget.novelId}/${chapters.first.id}');
    }
  }

  void _jumpToChapter(int totalChapters) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jump to Chapter'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter chapter number (1-$totalChapters)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final input = int.tryParse(controller.text);
              if (input != null && input >= 1 && input <= totalChapters) {
                final index = input - 1;
                _itemScrollController.scrollTo(
                  index: index,
                  duration: const Duration(milliseconds: 300),
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  void _triggerCloudflareBypass() async {
    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(widget.novelId);
    if (novel == null) return;

    final url = novel.url;
    if (!mounted) return;

    final handler = CloudflareHandler();
    final success = await handler.bypass(context, url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Cloudflare bypass successful! Try loading chapters again.'
              : 'Cloudflare bypass failed or was skipped.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapterDao = ref.watch(chapterDaoProvider);
    final libraryDao = ref.watch(libraryDaoProvider);
    final novel = _novel;

    final genres = novel?.genres != null
        ? (novel!.genres as String).split(',').where((g) => g.trim().isNotEmpty).toList()
        : <String>[];

    if (_novelLoaded && novel == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.book_outlined, size: 64, color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              const Text('Novel not found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _showDownloadDialog(context, ref),
            tooltip: 'Download',
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () {},
            tooltip: 'Filter',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'cloudflare') _triggerCloudflareBypass();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'cloudflare',
                child: Row(
                  children: [
                    Icon(Icons.shield, size: 20),
                    SizedBox(width: 8),
                    Text('Cloudflare Bypass'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<Chapter>>(
        stream: chapterDao.watchChaptersForNovel(widget.novelId),
        builder: (context, chapterSnapshot) {
          final chapters = chapterSnapshot.data ?? [];
          final isLoadingChapters = chapterSnapshot.connectionState == ConnectionState.waiting;

          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Header: Cover + Info
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: novel?.coverUrl != null
                            ? Image.network(
                                novel!.coverUrl!,
                                width: 105,
                                height: 145,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 105,
                                  height: 145,
                                  color: AppTheme.kSurfaceVariantDark,
                                  child: const Icon(Icons.book, size: 40),
                                ),
                              )
                            : Container(
                                width: 105,
                                height: 145,
                                color: AppTheme.kSurfaceVariantDark,
                                child: const Icon(Icons.book, size: 40),
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              novel?.title ?? 'Loading...',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.person_outline, size: 16, color: AppTheme.kTextSecondaryDark),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    novel?.author ?? 'Unknown author',
                                    style: const TextStyle(fontSize: 13, color: AppTheme.kTextSecondaryDark),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 16, color: AppTheme.kTextSecondaryDark),
                                const SizedBox(width: 4),
                                Text(
                                  novel?.status ?? 'Ongoing',
                                  style: const TextStyle(fontSize: 13, color: AppTheme.kTextSecondaryDark),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Action Icon Buttons (In Library, Track, WebView, etc.)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildActionButton(
                        icon: Icons.favorite,
                        label: 'In library',
                        isSelected: true,
                        onTap: () async {
                          final status = await showModalBottomSheet<String>(
                            context: context,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            builder: (ctx) => const StatusPickerSheet(),
                          );
                          if (status == null) return;
                          if (status == 'None') {
                            await libraryDao.removeFromLibrary(widget.novelId);
                          } else {
                            await libraryDao.addToLibrary(widget.novelId, status: status);
                          }
                        },
                      ),
                      _buildActionButton(
                        icon: Icons.hourglass_empty,
                        label: 'Soon',
                        isSelected: false,
                        onTap: () {},
                      ),
                      _buildActionButton(
                        icon: Icons.sync,
                        label: 'Tracking',
                        isSelected: false,
                        onTap: () {},
                      ),
                      _buildActionButton(
                        icon: Icons.language,
                        label: 'WebView',
                        isSelected: false,
                        onTap: _triggerCloudflareBypass,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description
                  if (novel?.description != null && novel!.description!.isNotEmpty) ...[
                    Text(
                      novel.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Genres / Tags Chips
                  if (genres.isNotEmpty) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: genres
                            .map((g) => Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Text(
                                    g.trim(),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Chapter Header count
                  Text(
                    '${chapters.length} chapters',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  // Chapters inline list or shimmer loading
                  if (isLoadingChapters)
                    const ShimmerList()
                  else if (chapters.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No chapters available.',
                          style: TextStyle(color: AppTheme.kTextSecondaryDark),
                        ),
                      ),
                    )
                  else
                    ...chapters.map((chapter) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            chapter.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: chapter.read ? FontWeight.normal : FontWeight.w600,
                              color: chapter.read ? AppTheme.kTextSecondaryDark : Colors.white,
                            ),
                          ),
                          subtitle: const Text(
                            'Available',
                            style: TextStyle(fontSize: 11, color: AppTheme.kTextSecondaryDark),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              chapter.downloaded ? Icons.download_done : Icons.arrow_circle_down_outlined,
                              size: 20,
                              color: AppTheme.kTextSecondaryDark,
                            ),
                            onPressed: () {},
                          ),
                          onTap: () => context.push('/reader/${widget.novelId}/${chapter.id}'),
                        )),
                  const SizedBox(height: 80),
                ],
              ),

              // Floating Play / Resume Button
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.extended(
                  onPressed: () => _playFromStart(ref),
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final color = isSelected ? AppTheme.kPrimary : AppTheme.kTextSecondaryDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
}