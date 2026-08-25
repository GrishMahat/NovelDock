import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../core/providers/engine.dart';
import '../../core/network/client.dart';
import '../../core/utils/platform.dart';
import '../../theme/tokens.dart';
import '../../widgets/max_width_box.dart';
import '../../widgets/page_header.dart';
import '../../core/network/cloudflare.dart';
import '../../widgets/shimmer_list.dart';
import '../downloads/providers/download_provider.dart';
import 'widgets/status_picker_sheet.dart';
import 'widgets/download_range_sheet.dart';

enum ChapterSort { indexAsc, indexDesc, nameAsc, nameDesc }

/// Novel detail screen. Shows novel info with tabs: Novel, Reviews, Related, Chapters.
class NovelDetailScreen extends ConsumerStatefulWidget {
  final int novelId;
  const NovelDetailScreen({super.key, required this.novelId});

  @override
  ConsumerState<NovelDetailScreen> createState() => _NovelDetailScreenState();
}

class _NovelDetailScreenState extends ConsumerState<NovelDetailScreen> {
  StreamSubscription? _novelSubscription;

  Novel? _novel;
  bool _novelLoaded = false;
  bool _isRefreshing = false;
  bool _initialLoading = true;

  /// Memoized so StreamBuilder keeps its subscription across rebuilds;
  /// recreating the stream each build resets connectionState to waiting
  /// and flashes the chapter skeleton.
  Stream<List<Chapter>>? _chaptersStream;
  ChapterSort _chapterSort = ChapterSort.indexAsc;

  @override
  void initState() {
    super.initState();
    _watchNovel();
  }

  void _watchNovel() {
    final novelDao = ref.read(novelDaoProvider);
    _novelSubscription = novelDao.watchNovelById(widget.novelId).listen((
      novel,
    ) {
      if (mounted) {
        setState(() {
          _novel = novel;
          _novelLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _novelSubscription?.cancel();
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
        builder: (ctx) => DownloadRangeSheet(
          totalChapters: chapters.length,
          minChapter: minChapter,
          maxChapter: maxChapter,
          onDownloadAll: () {
            Navigator.pop(ctx);
            ref
                .read(downloadProvider.notifier)
                .downloadAllChapters(widget.novelId);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloading ${chapters.length} chapters'),
              ),
            );
          },
          onDownloadRange: (start, end) {
            Navigator.pop(ctx);
            ref
                .read(downloadProvider.notifier)
                .downloadChapterRange(
                  widget.novelId,
                  start.round(),
                  end.round(),
                );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No chapters to play')));
      }
      return;
    }
    if (mounted) {
      context.push('/reader/${widget.novelId}/${chapters.first.id}');
    }
  }

  /// Fullscreen, pinch-zoomable cover viewer. Tap anywhere or the close
  /// button to dismiss.
  void _showCoverViewer(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(Insets.sm),
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ],
        ),
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
          content: Text(
            success
                ? 'Cloudflare bypass successful! Try loading chapters again.'
                : 'Cloudflare bypass failed or was skipped.',
          ),
        ),
      );
    }
  }

  Future<void> _refreshNovel() async {
    if (_novel == null) return;
    setState(() => _isRefreshing = true);

    try {
      final novelDao = ref.read(novelDaoProvider);
      final chapterDao = ref.read(chapterDaoProvider);
      final instance = await loadProviderById(
        _novel!.providerId,
        ref.container,
      );
      if (instance != null) {
        final novelUrl = await instance.getNovelInfoUrl(_novel!.url);
        if (novelUrl != null) {
          final dio = await ref.read(dioProvider.future);
          final response = await dio.get(novelUrl);
          final info = await instance.parseNovelInfo(response.data.toString());
          if (info != null && mounted) {
            await novelDao.updateNovel(
              NovelsCompanion(
                id: Value(widget.novelId),
                providerId: Value(_novel!.providerId),
                url: Value(_novel!.url),
                title: Value(info.title),
                author: Value(info.author),
                coverUrl: Value(info.cover ?? _novel!.coverUrl),
                description: Value(info.description),
                genres: Value(info.genres.join(',')),
                status: Value(info.status),
                addedAt: Value(DateTime.now().millisecondsSinceEpoch),
              ),
            );
            final chapterList = <ChaptersCompanion>[];
            for (var i = 0; i < info.chapters.length; i++) {
              final ch = info.chapters[i];
              chapterList.add(
                ChaptersCompanion(
                  novelId: Value(widget.novelId),
                  name: Value(ch.name),
                  url: Value(ch.url),
                  index: Value(i.toDouble()),
                ),
              );
            }
            await chapterDao.insertChaptersForNovel(
              widget.novelId,
              chapterList,
            );
            if (mounted) {
              final updated = await novelDao.getNovelById(widget.novelId);
              setState(() => _novel = updated);
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _isRefreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final chapterDao = ref.watch(chapterDaoProvider);
    final libraryDao = ref.watch(libraryDaoProvider);
    final novel = _novel;

    final genres = novel?.genres != null
        ? (novel!.genres as String)
              .split(',')
              .where((g) => g.trim().isNotEmpty)
              .toList()
        : <String>[];

    if (_novelLoaded && novel == null) {
      return Scaffold(
        appBar: isDesktop ? null : AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.book_outlined,
                size: 64,
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: Insets.lg),
              Text(
                'Novel not found',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Insets.sm),
              FilledButton.tonal(
                onPressed: () => context.pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: isDesktop ? null : AppBar(actions: _buildActions(context)),
      body: isDesktop
          ? Column(
              children: [
                PageHeader(
                  title: novel?.title ?? 'Novel',
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => context.pop(),
                  ),
                  actions: _buildActions(context),
                ),
                Expanded(
                  child: _buildBody(chapterDao, libraryDao, novel, genres),
                ),
              ],
            )
          : _buildBody(chapterDao, libraryDao, novel, genres),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.download),
        onPressed: () => _showDownloadDialog(context, ref),
        tooltip: 'Download',
      ),
      PopupMenuButton<ChapterSort>(
        icon: const Icon(Icons.sort),
        initialValue: _chapterSort,
        tooltip: 'Sort chapters',
        onSelected: (value) => setState(() => _chapterSort = value),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: ChapterSort.indexAsc,
            child: Row(
              children: [
                Icon(
                  _chapterSort == ChapterSort.indexAsc ? Icons.check : null,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text('Index 1\u21929'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ChapterSort.indexDesc,
            child: Row(
              children: [
                Icon(
                  _chapterSort == ChapterSort.indexDesc ? Icons.check : null,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text('Index 9\u21921'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ChapterSort.nameAsc,
            child: Row(
              children: [
                Icon(
                  _chapterSort == ChapterSort.nameAsc ? Icons.check : null,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text('Name A\u2192Z'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ChapterSort.nameDesc,
            child: Row(
              children: [
                Icon(
                  _chapterSort == ChapterSort.nameDesc ? Icons.check : null,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text('Name Z\u2192A'),
              ],
            ),
          ),
        ],
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
    ];
  }

  Widget _buildBody(
    ChapterDao chapterDao,
    LibraryDao libraryDao,
    Novel? novel,
    List<String> genres,
  ) {
    return StreamBuilder<List<Chapter>>(
      stream: _chaptersStream ??= ref
          .watch(chapterDaoProvider)
          .watchChaptersForNovel(widget.novelId),
      builder: (context, chapterSnapshot) {
        final chapters = chapterSnapshot.data ?? [];
        final sortedChapters = List<Chapter>.from(chapters)
          ..sort((a, b) {
            switch (_chapterSort) {
              case ChapterSort.indexAsc:
                return a.index.compareTo(b.index);
              case ChapterSort.indexDesc:
                return b.index.compareTo(a.index);
              case ChapterSort.nameAsc:
                return a.name.compareTo(b.name);
              case ChapterSort.nameDesc:
                return b.name.compareTo(a.name);
            }
          });
        // Only show the skeleton when there is nothing to show yet;
        // re-emissions and rebuilds must never blank an existing list.
        final isLoadingChapters =
            chapterSnapshot.connectionState == ConnectionState.waiting &&
            sortedChapters.isEmpty;
        final hasDescription =
            novel?.description != null && novel!.description!.isNotEmpty;
        final showChapterShimmer =
            isLoadingChapters ||
            (sortedChapters.isEmpty &&
                (!hasDescription || _initialLoading || _isRefreshing));

        if (sortedChapters.isNotEmpty) {
          _initialLoading = false;
        } else if (chapterSnapshot.connectionState == ConnectionState.active &&
            hasDescription) {
          _initialLoading = false;
        }

        return Stack(
          children: [
            RefreshIndicator(
              onRefresh: _refreshNovel,
              child: MaxWidthBox(
                padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // Header: Cover + Info
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: novel?.coverUrl == null
                              ? null
                              : () => _showCoverViewer(novel!.coverUrl!),
                          child: Tooltip(
                            message: 'View cover',
                            child: ClipRRect(
                              borderRadius: BorderRadius.all(Radii.md),
                              child: novel?.coverUrl != null
                                  ? Image.network(
                                      novel!.coverUrl!,
                                      width: 105,
                                      height: 145,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        width: 105,
                                        height: 145,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                        child: const Icon(Icons.book, size: 40),
                                      ),
                                    )
                                  : Container(
                                      width: 105,
                                      height: 145,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      child: const Icon(Icons.book, size: 40),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isDesktop)
                                Text(
                                  novel?.title ?? 'Loading...',
                                  style: Theme.of(context).textTheme.titleLarge,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (!isDesktop) const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      novel?.author ?? 'Unknown author',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    novel?.status ?? 'Ongoing',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
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
                              builder: (ctx) => const StatusPickerSheet(),
                            );
                            if (status == null) return;
                            if (status == 'None') {
                              await libraryDao.removeFromLibrary(
                                widget.novelId,
                              );
                            } else {
                              await libraryDao.addToLibrary(
                                widget.novelId,
                                status: status,
                              );
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
                          icon: Icons.language,
                          label: 'WebView',
                          isSelected: false,
                          onTap: _triggerCloudflareBypass,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Description
                    if (novel?.description != null &&
                        novel!.description!.isNotEmpty) ...[
                      _ExpandableDescription(description: novel.description!),
                      const SizedBox(height: 12),
                    ],

                    // Genres / Tags Chips
                    if (genres.isNotEmpty) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: genres
                              .map(
                                (g) => Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.all(Radii.md),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                    ),
                                  ),
                                  child: Text(
                                    g.trim(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Chapter Header count
                    if (!showChapterShimmer) ...[
                      Text(
                        '${sortedChapters.length} chapters',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: Insets.md),
                    ],

                    // Chapters inline list or shimmer loading
                    if (showChapterShimmer)
                      ...List.generate(8, (_) => const ShimmerChapterTile())
                    else if (sortedChapters.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No chapters available.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    else
                      ...sortedChapters.map(
                        (chapter) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            chapter.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: chapter.read
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                              color: chapter.read
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            'Available',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              chapter.downloaded
                                  ? Icons.download_done
                                  : Icons.arrow_circle_down_outlined,
                              size: 20,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () {},
                          ),
                          onTap: () => context.push(
                            '/reader/${widget.novelId}/${chapter.id}',
                          ),
                        ),
                      ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),

            // Floating Play / Resume Button
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => _playFromStart(ref),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                icon: const Icon(Icons.play_arrow),
                label: const Text(
                  'Resume',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.all(Radii.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: Insets.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableDescription extends StatefulWidget {
  final String description;
  const _ExpandableDescription({required this.description});

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final clean = widget.description.replaceAll(RegExp(r'\s+'), ' ').trim();
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clean,
            maxLines: _expanded ? null : 2,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
