import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/text_utils.dart';
import '../../theme/app_theme.dart';
import '../../core/tts/tts_manager.dart';
import '../downloads/providers/download_provider.dart';

/// Novel detail screen — shows novel info with tabs: Novel, Reviews, Related, Chapters.
class NovelDetailScreen extends ConsumerStatefulWidget {
  final int novelId;
  const NovelDetailScreen({super.key, required this.novelId});

  @override
  ConsumerState<NovelDetailScreen> createState() => _NovelDetailScreenState();
}

class _NovelDetailScreenState extends ConsumerState<NovelDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        builder: (ctx) => _DownloadSheet(
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

  @override
  Widget build(BuildContext context) {
    final novelDao = ref.watch(novelDaoProvider);
    final chapterDao = ref.watch(chapterDaoProvider);
    final libraryDao = ref.watch(libraryDaoProvider);

    Log.i('NovelDetail', 'Building for novelId=${widget.novelId}');

    return Scaffold(
      body: FutureBuilder<Novel?>(
        future: novelDao.getNovelById(widget.novelId),
        builder: (context, novelSnapshot) {
          final novel = novelSnapshot.data;
          Log.i('NovelDetail', 'getNovelById(${widget.novelId}): ${novel != null ? 'found title="${novel.title}"' : 'null'}');

          return CustomScrollView(
            slivers: [
              // App bar with cover image background
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    novel?.title ?? 'Novel #${widget.novelId}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  background: novel?.coverUrl != null
                      ? Image.network(
                          novel!.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppTheme.kSurfaceVariantDark,
                            child:
                                const Icon(Icons.book, size: 64),
                          ),
                        )
                      : Container(
                          color: AppTheme.kSurfaceVariantDark,
                          child:
                              const Icon(Icons.book, size: 64),
                        ),
                ),
              ),

              // Novel info header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        novel?.title ?? 'Loading...',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (novel?.author != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          novel!.author!,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.kTextSecondaryDark,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Status
                      if (novel?.status != null) ...[
                        _buildStatusChip(novel!.status!),
                        const SizedBox(height: 12),
                      ],
                      // Description
                      if (novel?.description != null &&
                          novel!.description!.isNotEmpty) ...[
                        Text(
                          novel.description!,
                          style: const TextStyle(fontSize: 14, height: 1.5),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final status = await showModalBottomSheet<String>(
                                  context: context,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                  ),
                                  builder: (ctx) => _StatusPickerSheet(),
                                );
                                if (status == null) return;
                                if (status == 'None') {
                                  await libraryDao.removeFromLibrary(widget.novelId);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Removed from Library')),
                                    );
                                  }
                                } else {
                                  await libraryDao.addToLibrary(
                                    widget.novelId,
                                    status: status,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Added to Library ($status)')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.library_add, size: 18),
                              label: const Text('Library'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Play TTS button
                          FilledButton.tonalIcon(
                            onPressed: () => _playFromStart(ref),
                            icon: const Icon(Icons.play_arrow, size: 20),
                            label: const Text('Play'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _showDownloadDialog(context, ref),
                              icon: const Icon(Icons.download, size: 18),
                              label: const Text('Download'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Tab bar
              SliverToBoxAdapter(
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Info'),
                    Tab(text: 'Chapters'),
                  ],
                ),
              ),

              // Tab content
              SliverFillRemaining(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildInfoTab(novel),
                    _buildChaptersTab(chapterDao),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final color =
        status.toLowerCase().contains('ongoing') ? AppTheme.kOngoing : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoTab(Novel? novel) {
    if (novel == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final genres = novel.genres != null
        ? (novel.genres as String).split(',').where((g) => g.trim().isNotEmpty).toList()
        : <String>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (genres.isNotEmpty) ...[
            const Text(
              'Genres',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: genres
                  .map((g) => Chip(
                        label: Text(g.trim(),
                            style: const TextStyle(fontSize: 11)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],
          if (novel.description != null &&
              novel.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Description',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              novel.description!,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChaptersTab(ChapterDao chapterDao) {
    return StreamBuilder<List<Chapter>>(
      stream: chapterDao.watchChaptersForNovel(widget.novelId),
      builder: (context, snapshot) {
        final chapters = snapshot.data ?? [];
        Log.i('NovelDetail', 'Chapters tab: connectionState=${snapshot.connectionState} chapters=${chapters.length}');

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (chapters.isEmpty) {
          return const Center(
            child: Text(
              'No chapters available.\nThis novel may not have been loaded yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.kTextSecondaryDark),
            ),
          );
        }

        return Stack(
          children: [
            ScrollablePositionedList.builder(
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final isRead = chapter.read;
                return ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: isRead
                        ? Colors.green.withValues(alpha: 0.15)
                        : AppTheme.kSurfaceVariantDark,
                    child: isRead
                        ? const Icon(Icons.check, size: 14, color: Colors.green)
                        : Text(
                            '${index + 1}',
                            style: const TextStyle(fontSize: 12),
                          ),
                  ),
                  title: Text(
                    chapter.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isRead ? AppTheme.kTextSecondaryDark : null,
                      fontWeight: isRead ? FontWeight.normal : FontWeight.w500,
                    ),
                  ),
                  subtitle: isRead ? const Text('Read', style: TextStyle(fontSize: 11, color: Colors.green)) : null,
                  trailing: Icon(
                    chapter.downloaded ? Icons.download_done : null,
                    size: 16,
                    color: AppTheme.kTextSecondaryDark,
                  ),
                  onTap: () {
                    context.push('/reader/${widget.novelId}/${chapter.id}');
                  },
                );
              },
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                heroTag: 'jump_to_chapter',
                onPressed: () => _jumpToChapter(chapters.length),
                child: const Icon(Icons.sort),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatusPickerSheet extends StatefulWidget {
  const _StatusPickerSheet();

  @override
  State<_StatusPickerSheet> createState() => _StatusPickerSheetState();
}

class _StatusPickerSheetState extends State<_StatusPickerSheet> {
  String _selected = 'Reading';

  static const _options = [
    'Reading',
    'On Hold',
    'Plan to Read',
    'Completed',
    'Dropped',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Add to Library',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._options.map((s) => ListTile(
            title: Text(s),
            trailing: _selected == s ? const Icon(Icons.check, size: 20) : null,
            onTap: () => setState(() => _selected = s),
          )),
          const Divider(),
          ListTile(
            leading: Icon(Icons.remove_circle, color: Colors.red.shade400),
            title: Text('None', style: TextStyle(color: Colors.red.shade400)),
            trailing: _selected == 'None' ? Icon(Icons.check, size: 20, color: Colors.red.shade400) : null,
            onTap: () => setState(() => _selected = 'None'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4, bottom: 16),
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 16, bottom: 16),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('OK'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DownloadSheet extends StatefulWidget {
  final int totalChapters;
  final double minChapter;
  final double maxChapter;
  final VoidCallback onDownloadAll;
  final void Function(double start, double end) onDownloadRange;

  const _DownloadSheet({
    required this.totalChapters,
    required this.minChapter,
    required this.maxChapter,
    required this.onDownloadAll,
    required this.onDownloadRange,
  });

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  bool _useRange = false;
  late RangeValues _range;

  @override
  void initState() {
    super.initState();
    _range = RangeValues(widget.minChapter, widget.maxChapter);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 32, height: 4,
            decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text('Download Chapters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Download range'),
            subtitle: Text('Select chapter range (${widget.totalChapters} total)'),
            value: _useRange,
            onChanged: (v) => setState(() => _useRange = v),
          ),
          if (_useRange) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Text('Chapters ${_range.start.round()} - ${_range.end.round()}'),
                  RangeSlider(
                    values: _range,
                    min: widget.minChapter,
                    max: widget.maxChapter,
                    divisions: (widget.maxChapter - widget.minChapter).toInt().clamp(1, 100),
                    labels: RangeLabels('${_range.start.round()}', '${_range.end.round()}'),
                    onChanged: (v) => setState(() => _range = v),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 4, bottom: 16),
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 16, bottom: 16),
                  child: FilledButton(
                    onPressed: _useRange
                        ? () => widget.onDownloadRange(_range.start, _range.end)
                        : widget.onDownloadAll,
                    child: Text(_useRange ? 'Download Range' : 'Download All'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
