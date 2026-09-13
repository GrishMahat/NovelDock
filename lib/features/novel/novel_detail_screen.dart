import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/database/database.dart';
import '../../core/network/client.dart' show dioProvider;
import '../../core/network/cloudflare.dart';
import '../../core/providers/database_providers.dart';
import '../../core/providers/novel_fetch_state.dart';
import '../../core/providers/novel_opener.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/platform.dart';
import '../../theme/tokens.dart';
import '../../widgets/max_width_box.dart';
import '../../widgets/page_header.dart';
import '../../widgets/shimmer_list.dart';
import '../browse/webview_screen.dart';
import '../downloads/providers/download_provider.dart';
import 'chapter_sort.dart';
import 'widgets/status_picker_sheet.dart';
import 'widgets/download_range_sheet.dart';

enum ChapterFilter { all, downloaded, bookmarked, read, unread }

extension ChapterFilterLabel on ChapterFilter {
  String get label => switch (this) {
    ChapterFilter.all => 'All',
    ChapterFilter.downloaded => 'Downloaded',
    ChapterFilter.bookmarked => 'Bookmarked',
    ChapterFilter.read => 'Read',
    ChapterFilter.unread => 'Unread',
  };
}

const _tag = 'NovelDetail';

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

  /// Memoized so StreamBuilder keeps its subscription across rebuilds;
  /// recreating the stream each build resets connectionState to waiting
  /// and flashes the chapter skeleton.
  Stream<List<Chapter>>? _chaptersStream;
  ChapterSort _chapterSort = ChapterSort.normal;
  ChapterFilter _chapterFilter = ChapterFilter.all;

  /// Whether the open-time auto-fetch below has run. Guards both the fetch
  /// itself and the shimmer condition: idle + empty means "about to load"
  /// only before this flips.
  bool _autoFetchAttempted = false;

  @override
  void initState() {
    super.initState();
    _watchNovel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Verify this novel's downloads still exist on disk before the UI
      // claims them.
      ref
          .read(downloadProvider.notifier)
          .reconcileDownloads(novelId: widget.novelId);
      // Self-heal chapter lists: library/history/deep-link/import entries
      // land here directly without opener.open()'s background fetch, so a
      // novel with zero cached chapters would otherwise sit on a bogus
      // "No chapters available" with nothing ever loading.
      unawaited(_fetchChaptersIfNeeded());
    });
  }

  /// Fetches chapters once per screen instance when none are cached and no
  /// fetch is already running. Skips local imports (no remote source) and
  /// novels whose fetch already ran or is running (opener.open() path).
  Future<void> _fetchChaptersIfNeeded() async {
    if (_autoFetchAttempted || !mounted) return;
    _autoFetchAttempted = true;
    // Claim loading synchronously: the awaits below must not leave a frame
    // showing the empty state for content that is about to load.
    setState(() => _isRefreshing = true);
    try {
      final phase = ref.read(novelFetchStateProvider(widget.novelId)).phase;
      if (phase != NovelFetchPhase.idle) return;
      final novel =
          _novel ??
          await ref.read(novelDaoProvider).getNovelById(widget.novelId);
      if (!mounted || novel == null || novel.providerId == 'local') return;
      final chapters = await ref
          .read(chapterDaoProvider)
          .getChaptersForNovel(widget.novelId);
      if (!mounted || chapters.isNotEmpty) return;
      if (_novel == null) setState(() => _novel = novel);
      await _refreshNovel();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
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
                  child: Center(child: Image.network(url, fit: BoxFit.contain)),
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

  /// Opens the source in the in-app browser so a Cloudflare challenge can be
  /// verified. The source is probed first — the verification flow only opens
  /// when the source actually serves a challenge.
  Future<void> _triggerCloudflareBypass() async {
    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(widget.novelId);
    if (novel == null) return;

    var challenge = true;
    try {
      final dio = await ref.read(dioProvider.future);
      final response = await dio.get(novel.url);
      challenge = CloudflareHandler.isCloudflareChallenge(response);
    } on DioException catch (e) {
      final response = e.response;
      challenge =
          response == null || CloudflareHandler.isCloudflareChallenge(response);
    } catch (e) {
      Log.w(_tag, 'Cloudflare probe failed, opening verification anyway: $e');
    }

    if (!mounted) return;
    if (!challenge) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No Cloudflare verification needed for this source.'),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewScreen(url: novel.url, title: novel.title),
      ),
    );
  }

  /// Opens the source page in the in-app browser.
  void _openInAppBrowser() {
    final novel = _novel;
    if (novel == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebViewScreen(url: novel.url, title: novel.title),
      ),
    );
  }

  Future<void> _refreshNovel() async {
    if (_novel == null) return;
    setState(() => _isRefreshing = true);

    try {
      // Delegates to NovelOpener.refreshNovel — the single fetch/parse/
      // insert pipeline, which also preserves Novels.addedAt.
      final ok = await ref
          .read(novelOpenerProvider)
          .refreshNovel(widget.novelId);
      if (!mounted) return;

      if (ok) {
        final updated = await ref
            .read(novelDaoProvider)
            .getNovelById(widget.novelId);
        if (mounted) setState(() => _novel = updated);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Refresh failed')));
      }
    } catch (e) {
      Log.w(_tag, 'Refresh failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Refresh failed')));
      }
    } finally {
      // The early return above used to leak _isRefreshing=true, sticking
      // the shimmer on forever with no fetch running behind it.
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Stable handles: one-shot calls only (the chapters stream is memoized
    // separately). Watching would resubscribe work on every rebuild.
    final chapterDao = ref.read(chapterDaoProvider);
    final libraryDao = ref.read(libraryDaoProvider);
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
          for (final sort in ChapterSort.values)
            PopupMenuItem(
              value: sort,
              child: Row(
                children: [
                  Icon(_chapterSort == sort ? Icons.check : null, size: 18),
                  const SizedBox(width: 8),
                  Text(sort.label),
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
                Text('Verify Cloudflare challenge'),
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
          .read(chapterDaoProvider)
          .watchChaptersForNovel(widget.novelId),
      builder: (context, chapterSnapshot) {
        final chapters = chapterSnapshot.data ?? [];
        final sortedChapters = sortChapters(chapters, _chapterSort);
        // Client-side status filter (mirrors the original's chapter filter
        // popup: downloaded / bookmarked / read / unread).
        final filteredChapters = switch (_chapterFilter) {
          ChapterFilter.all => sortedChapters,
          ChapterFilter.downloaded =>
            sortedChapters.where((c) => c.downloaded).toList(),
          ChapterFilter.bookmarked =>
            sortedChapters.where((c) => c.bookmarked).toList(),
          ChapterFilter.read => sortedChapters.where((c) => c.read).toList(),
          ChapterFilter.unread => sortedChapters.where((c) => !c.read).toList(),
        };
        // Only show the skeleton when there is nothing to show yet AND
        // chapters may still arrive; re-emissions must never blank an
        // existing list. The fetch phase is authoritative: an empty stream
        // while a background fetch is running is transient, not "zero".
        // Crucially, idle + empty ALSO means loading until the open-time
        // auto-fetch has run — otherwise a fresh novel flashes a bogus
        // "No chapters available" before anything even starts loading.
        // (Local imports are exempt: they have no remote source, so empty
        // really is empty for them.)
        final isLoadingChapters =
            chapterSnapshot.connectionState == ConnectionState.waiting &&
            sortedChapters.isEmpty;
        final fetchPhase = ref
            .watch(novelFetchStateProvider(widget.novelId))
            .phase;
        final showChapterShimmer =
            isLoadingChapters ||
            (sortedChapters.isEmpty &&
                (fetchPhase.isFetching ||
                    _isRefreshing ||
                    (fetchPhase == NovelFetchPhase.idle &&
                        !_autoFetchAttempted &&
                        _novel?.providerId != 'local')));

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
                          onTap: _openInAppBrowser,
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
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Chapter Header count + status filter chips
                    if (!showChapterShimmer && sortedChapters.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _chapterFilter == ChapterFilter.all
                                  ? '${sortedChapters.length} chapters'
                                  : '${filteredChapters.length} of ${sortedChapters.length} chapters',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (_chapterFilter != ChapterFilter.all)
                            TextButton(
                              onPressed: () => setState(
                                () => _chapterFilter = ChapterFilter.all,
                              ),
                              child: const Text('Clear'),
                            ),
                        ],
                      ),
                      const SizedBox(height: Insets.sm),
                      Wrap(
                        spacing: 8,
                        children: ChapterFilter.values.map((filter) {
                          return FilterChip(
                            label: Text(filter.label),
                            selected: _chapterFilter == filter,
                            onSelected: (_) =>
                                setState(() => _chapterFilter = filter),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: Insets.md),
                    ],

                    // Chapters inline list or shimmer loading
                    if (showChapterShimmer)
                      ...List.generate(8, (_) => const ShimmerChapterTile())
                    else if (filteredChapters.isEmpty &&
                        _chapterFilter != ChapterFilter.all &&
                        sortedChapters.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Text(
                              'No ${_chapterFilter.label.toLowerCase()} chapters.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: Insets.md),
                            OutlinedButton(
                              onPressed: () => setState(
                                () => _chapterFilter = ChapterFilter.all,
                              ),
                              child: const Text('Show all chapters'),
                            ),
                          ],
                        ),
                      )
                    else if (sortedChapters.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Text(
                              fetchPhase == NovelFetchPhase.failed
                                  ? 'Could not load chapters.'
                                  : 'No chapters available.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: Insets.md),
                            OutlinedButton.icon(
                              onPressed: _isRefreshing
                                  ? null
                                  : () => unawaited(_refreshNovel()),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text(
                                fetchPhase == NovelFetchPhase.failed
                                    ? 'Retry'
                                    : 'Check for chapters',
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...filteredChapters.map(
                        (chapter) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            chapter.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.fontSize,
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
                              fontSize: Theme.of(
                                context,
                              ).textTheme.labelSmall?.fontSize,
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
                            tooltip: chapter.downloaded
                                ? 'Downloaded'
                                : 'Download chapter',
                            onPressed: chapter.downloaded
                                ? null
                                : () => ref
                                      .read(downloadProvider.notifier)
                                      .downloadChapter(
                                        widget.novelId,
                                        chapter.id,
                                      ),
                          ),
                          onTap: () => context.push(
                            '/reader/${widget.novelId}/${chapter.id}',
                          ),
                        ),
                      ),
                    _HighlightsSection(novel: novel, chapters: sortedChapters),
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

/// Reader highlights for this novel, with Markdown export. Own widget so
/// annotation changes rebuild only this section, not the detail body.
class _HighlightsSection extends ConsumerWidget {
  final Novel? novel;
  final List<Chapter> chapters;

  const _HighlightsSection({required this.novel, required this.chapters});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotationsAsync = ref.watch(
      novelAnnotationsProvider(novel?.id ?? -1),
    );
    final annotations = annotationsAsync.value ?? const <Annotation>[];
    if (annotations.isEmpty) return const SizedBox.shrink();

    final chapterNames = {for (final c in chapters) c.id: c.name};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Insets.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                'Highlights (${annotations.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 20),
              tooltip: 'Export highlights',
              onPressed: () =>
                  _exportHighlights(context, ref, annotations, chapterNames),
            ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        for (final a in annotations)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              '“${a.quote}”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
            ),
            subtitle: Text(
              [
                chapterNames[a.chapterId] ?? 'Chapter',
                if (a.note != null && a.note!.isNotEmpty) a.note!,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Delete highlight',
              onPressed: () =>
                  ref.read(annotationDaoProvider).removeAnnotation(a.id),
            ),
            onTap: a.note == null || a.note!.isEmpty
                ? null
                : () => _viewNote(context, a),
          ),
      ],
    );
  }

  void _viewNote(BuildContext context, Annotation annotation) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Note'),
        content: SingleChildScrollView(child: Text(annotation.note!)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportHighlights(
    BuildContext context,
    WidgetRef ref,
    List<Annotation> annotations,
    Map<int, String> chapterNames,
  ) async {
    try {
      final title = novel?.title ?? 'Novel';
      final buf = StringBuffer(
        '# Highlights — $title\n\n'
        'Exported ${DateTime.now().toIso8601String().split('T').first} '
        'from NovelDock\n',
      );
      var currentChapter = '';
      for (final a in annotations) {
        final chapter = chapterNames[a.chapterId] ?? 'Chapter';
        if (chapter != currentChapter) {
          currentChapter = chapter;
          buf.writeln('\n## $chapter\n');
        }
        buf.writeln('> ${a.quote}\n');
        if (a.note != null && a.note!.isNotEmpty) {
          buf.writeln('Note: ${a.note}\n');
        }
      }

      final dir = await getTemporaryDirectory();
      final safeTitle = title
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '-')
          .toLowerCase();
      final file = File(
        '${dir.path}/noveldock-highlights-${safeTitle.isEmpty ? 'novel' : safeTitle}.md',
      );
      await file.writeAsString(buf.toString());

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Highlights — $title'),
      );
      Log.i('NovelDetail', 'Exported ${annotations.length} highlight(s)');
    } catch (e) {
      Log.e('NovelDetail', 'Highlight export failed', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export failed — see logs')),
        );
      }
    }
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
              fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
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
