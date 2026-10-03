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
import '../../widgets/cover_image.dart';
import '../../widgets/max_width_box.dart';
import '../../widgets/page_header.dart';
import '../../widgets/shimmer_list.dart';
import '../browse/webview_screen.dart';
import '../downloads/providers/download_provider.dart';
import 'chapter_sort.dart';
import 'widgets/status_picker_sheet.dart';
import 'widgets/download_range_sheet.dart';

enum ChapterFilter { all, downloaded, bookmarked, read, unread }

/// Per-novel overflow actions. Chapter-level actions live in selection mode
/// instead, so this list stays short.
enum _NovelMenuAction { selectChapters, refresh, cloudflare }

/// Long-press actions on a single chapter row.
enum _ChapterRowAction {
  selectFromHere,
  markBeforeRead,
  addBookmark,
  removeBookmark,
}

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
  StreamSubscription? _librarySubscription;

  Novel? _novel;
  bool _novelLoaded = false;
  bool _isRefreshing = false;

  /// Library membership status (Reading/On Hold/…). Null when the novel is
  /// not in the library. Tracked separately because Novel.status is provider
  /// metadata (Ongoing/Completed), not membership.
  String? _libraryStatus;

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

  /// Chapter ids picked in selection mode. Empty until the user taps rows,
  /// so selection mode is armed separately by [_selectionArmed].
  final Set<int> _selectedChapterIds = <int>{};

  /// Selection mode is armed by the overflow menu (or a long press) and stays
  /// armed with zero picks, so "Select chapters" has somewhere to go before
  /// the first tap.
  bool _selectionArmed = false;

  bool get _selecting => _selectionArmed;

  void _armSelection() => setState(() {
    _selectionArmed = true;
    // A snackbar from the last bulk action sits exactly where the selection
    // bar goes and would swallow taps on it.
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  });

  void _toggleSelection(int chapterId) {
    setState(() {
      if (!_selectedChapterIds.remove(chapterId)) {
        _selectedChapterIds.add(chapterId);
      }
    });
  }

  void _clearSelection() => setState(() {
    _selectedChapterIds.clear();
    _selectionArmed = false;
  });

  /// Selects every chapter currently visible under the active filter, so
  /// "select all" means what the user is looking at rather than the whole
  /// novel hidden behind a filter.
  void _selectAllVisible(List<Chapter> visible) {
    setState(() {
      if (_selectedChapterIds.length == visible.length) {
        _selectedChapterIds.clear();
        return;
      }
      _selectedChapterIds
        ..clear()
        ..addAll(visible.map((c) => c.id));
    });
  }

  /// Chapters currently rendered under the active filter. Bulk actions need
  /// this to resolve picked ids back to rows without re-querying.
  List<Chapter> _lastVisibleChapters = const [];

  /// Runs [action] over the selection, reports the outcome, then leaves
  /// selection mode.
  Future<void> _runOnSelection(
    String verb,
    Future<void> Function(Chapter chapter) action,
    List<Chapter> allChapters,
  ) async {
    final ids = _selectedChapterIds.toList();
    final targets = allChapters.where((c) => ids.contains(c.id)).toList();
    if (targets.isEmpty) return;

    for (final chapter in targets) {
      await action(chapter);
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    _clearSelection();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$verb ${targets.length} chapter(s)')),
      );
  }

  @override
  void initState() {
    super.initState();
    _watchNovel();
    _watchLibrary();
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

  void _watchLibrary() {
    final libraryDao = ref.read(libraryDaoProvider);
    _librarySubscription = libraryDao.watchAllLibraryEntries().listen((
      entries,
    ) {
      if (!mounted) return;
      LibraryData? match;
      for (final e in entries) {
        if (e.novelId == widget.novelId) {
          match = e;
          break;
        }
      }
      final status = match?.status;
      if (status != _libraryStatus) {
        setState(() => _libraryStatus = status);
      }
    });
  }

  @override
  void dispose() {
    _novelSubscription?.cancel();
    _librarySubscription?.cancel();
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
                    child: CoverImage(imageUrl: url, fit: BoxFit.contain),
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
      appBar: isDesktop
          ? null
          : AppBar(
              title: _headerTitle == null ? null : Text(_headerTitle!),
              actions: _buildActions(context),
            ),
      body: isDesktop
          ? Column(
              children: [
                PageHeader(
                  title: _headerTitle ?? novel?.title ?? 'Novel',
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

  /// Header actions. The list is deliberately identical in both states so the
  /// overflow button's RenderBox is never disposed: the popup route reads its
  /// anchor while animating out, and swapping the anchor mid-animation made it
  /// lay out against a dead box (a 151px overflow on every screen size).
  List<Widget> _buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.download),
        onPressed: _selecting ? null : () => _showDownloadDialog(context, ref),
        tooltip: 'Download',
      ),
      PopupMenuButton<_NovelMenuAction>(
        key: const ValueKey('novel-overflow'),
        icon: const Icon(Icons.more_vert),
        tooltip: 'More actions',
        onSelected: (action) => _onNovelMenuAction(context, action),
        itemBuilder: (context) => [
          _menuItem(
            context,
            _NovelMenuAction.selectChapters,
            Icons.checklist,
            'Select chapters',
          ),
          _menuItem(
            context,
            _NovelMenuAction.refresh,
            Icons.refresh,
            'Refresh details',
          ),
          const PopupMenuDivider(),
          _menuItem(
            context,
            _NovelMenuAction.cloudflare,
            Icons.shield_outlined,
            'Verify Cloudflare challenge',
          ),
        ],
      ),
    ];
  }

  void _onNovelMenuAction(BuildContext context, _NovelMenuAction action) {
    switch (action) {
      case _NovelMenuAction.selectChapters:
        _armSelection();
      case _NovelMenuAction.refresh:
        unawaited(_refreshNovel());
      case _NovelMenuAction.cloudflare:
        unawaited(_triggerCloudflareBypass());
    }
  }

  /// Bottom selection bar. Lives at the bottom rather than in the app bar
  /// because all six verbs need real estate the title row cannot spare, and
  /// because on a phone that is where the thumb already is.
  Widget _buildSelectionBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allPicked =
        _lastVisibleChapters.isNotEmpty &&
        _selectedChapterIds.length == _lastVisibleChapters.length;
    final count = _selectedChapterIds.length;

    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.sm,
            vertical: Insets.xs,
          ),
          child: Row(
            children: [
              _BarAction(
                icon: Icons.close,
                label: 'Cancel',
                onPressed: _clearSelection,
              ),
              _BarAction(
                icon: allPicked ? Icons.deselect : Icons.done_all,
                label: allPicked ? 'Select none' : 'Select all',
                onPressed: allPicked
                    ? () => setState(_selectedChapterIds.clear)
                    : () => _selectAllVisible(_lastVisibleChapters),
              ),
              const Spacer(),
              _BarAction(
                icon: Icons.download_outlined,
                label: 'Download',
                enabled: count > 0,
                onPressed: () => _bulkDownload(context),
              ),
              _BarAction(
                icon: Icons.bookmark_add_outlined,
                label: 'Bookmark',
                enabled: count > 0,
                onPressed: () => _bulkBookmark(context, true),
              ),
              _BarAction(
                icon: Icons.bookmark_remove_outlined,
                label: 'Unmark',
                enabled: count > 0,
                onPressed: () => _bulkBookmark(context, false),
              ),
              _BarAction(
                icon: Icons.mark_email_read_outlined,
                label: 'Mark read',
                enabled: count > 0,
                onPressed: () => _bulkRead(context, read: true),
              ),
              _BarAction(
                icon: Icons.mark_email_unread_outlined,
                label: 'Mark unread',
                enabled: count > 0,
                onPressed: () => _bulkRead(context, read: false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Header title: the pick count while selecting, otherwise the novel title.
  String? get _headerTitle =>
      _selecting ? '${_selectedChapterIds.length} selected' : null;

  /// Marks every chapter *before* [chapter] as read.
  ///
  /// The cross-provider resume case: you finish a novel on one source, find a
  /// source with the same novel carrying more chapters, and need everything up
  /// to where you stopped greyed out without tapping 400 rows. Chapters are
  /// matched on position within the currently visible, sorted list, so "before"
  /// means what the user can see rather than the provider's raw chapter ids.
  Future<void> _markBeforeAsRead(List<Chapter> visible, Chapter chapter) async {
    final index = visible.indexWhere((c) => c.id == chapter.id);
    if (index <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing before this chapter')),
        );
      }
      return;
    }
    final earlier = visible.sublist(0, index);
    final chapterDao = ref.read(chapterDaoProvider);
    var changed = 0;
    for (final c in earlier) {
      if (c.read) continue;
      await chapterDao.markChapterAsRead(c.id);
      changed++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            changed == 0
                ? 'Earlier chapters were already read'
                : 'Marked $changed earlier chapter(s) as read',
          ),
        ),
      );
  }

  /// Long-press menu on a chapter row. Kept as a sheet rather than a nested
  /// popup so the destructive-ish bulk verbs are unambiguous.
  Future<void> _showChapterRowMenu(
    BuildContext context,
    Chapter chapter,
    List<Chapter> visible,
  ) async {
    final action = await showModalBottomSheet<_ChapterRowAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.sm,
                Insets.lg,
                Insets.sm,
              ),
              child: Text(
                chapter.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_check),
              title: const Text('Select from here down'),
              onTap: () => Navigator.pop(ctx, _ChapterRowAction.selectFromHere),
            ),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('Mark earlier as read'),
              subtitle: const Text('Everything before this chapter'),
              onTap: () => Navigator.pop(ctx, _ChapterRowAction.markBeforeRead),
            ),
            ListTile(
              leading: Icon(
                chapter.bookmarked
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
              ),
              title: Text(chapter.bookmarked ? 'Remove bookmark' : 'Bookmark'),
              onTap: () => Navigator.pop(
                ctx,
                chapter.bookmarked
                    ? _ChapterRowAction.removeBookmark
                    : _ChapterRowAction.addBookmark,
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final chapterDao = ref.read(chapterDaoProvider);
    switch (action) {
      case _ChapterRowAction.selectFromHere:
        setState(() {
          _selectionArmed = true;
          _selectedChapterIds
            ..clear()
            ..addAll(
              visible.where((c) => c.index >= chapter.index).map((c) => c.id),
            );
        });
      case _ChapterRowAction.markBeforeRead:
        await _markBeforeAsRead(visible, chapter);
      case _ChapterRowAction.addBookmark:
        await chapterDao.toggleBookmark(chapter.id, true);
      case _ChapterRowAction.removeBookmark:
        await chapterDao.toggleBookmark(chapter.id, false);
    }
  }

  Future<void> _bulkDownload(BuildContext context) async {
    final notifier = ref.read(downloadProvider.notifier);
    await _runOnSelection(
      'Queued',
      (c) => notifier.downloadChapter(widget.novelId, c.id),
      _lastVisibleChapters,
    );
  }

  Future<void> _bulkBookmark(BuildContext context, bool bookmarked) async {
    final chapterDao = ref.read(chapterDaoProvider);
    await _runOnSelection(
      bookmarked ? 'Bookmarked' : 'Unbookmarked',
      (c) => chapterDao.toggleBookmark(c.id, bookmarked),
      _lastVisibleChapters,
    );
  }

  Future<void> _bulkRead(BuildContext context, {required bool read}) async {
    final chapterDao = ref.read(chapterDaoProvider);
    await _runOnSelection(
      read ? 'Marked read' : 'Marked unread',
      (c) => read
          ? chapterDao.markChapterAsRead(c.id)
          : chapterDao.markChapterAsUnread(c.id),
      _lastVisibleChapters,
    );
  }

  Future<void> _editLibraryStatus(
    BuildContext context,
    LibraryDao libraryDao,
  ) async {
    final status = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => StatusPickerSheet(
        title: _libraryStatus != null ? 'Set status' : 'Add to library',
        initialStatus: _libraryStatus,
      ),
    );
    if (status == null) return;
    if (status == 'None') {
      await libraryDao.removeFromLibrary(widget.novelId);
    } else {
      await libraryDao.addToLibrary(widget.novelId, status: status);
    }
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
        // Bulk actions resolve picked ids through this instead of re-querying.
        _lastVisibleChapters = filteredChapters;
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
                  // Room for the selection bar when it is present.
                  padding: EdgeInsets.only(
                    top: Insets.sm,
                    bottom: _selecting ? 72 : 80,
                  ),
                  children: [
                    // Header: cover + title/author/status, with the two
                    // per-novel actions (library, source page) moved up
                    // beside the cover. The old three-up action row also
                    // carried a dead "Soon" button whose onTap was a no-op.
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
                              child: CoverImage(
                                imageUrl: novel?.coverUrl,
                                title: novel?.title,
                                width: 96,
                                height: 132,
                                fontSize: 36,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isDesktop) ...[
                                Text(
                                  novel?.title ?? 'Loading...',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: Insets.xs),
                              ],
                              Row(
                                children: [
                                  Icon(
                                    Icons.person_outline,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: Insets.xs),
                                  Expanded(
                                    child: Text(
                                      novel?.author ?? 'Unknown author',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
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
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: Insets.xs),
                                  Flexible(
                                    child: Text(
                                      novel?.status ?? 'Ongoing',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
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
                              const SizedBox(height: Insets.sm),
                              // Library membership + source page sit with the
                              // metadata instead of claiming a full-width
                              // action row of their own.
                              Row(
                                children: [
                                  _HeaderAction(
                                    icon: _libraryStatus != null
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    label: _libraryStatus ?? 'Library',
                                    active: _libraryStatus != null,
                                    onTap: () =>
                                        _editLibraryStatus(context, libraryDao),
                                  ),
                                  const SizedBox(width: Insets.sm),
                                  _HeaderAction(
                                    icon: Icons.language,
                                    label: 'Source',
                                    active: false,
                                    onTap: _openInAppBrowser,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Insets.md),

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
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          // Sort belongs to the chapter list, not the novel,
                          // so it sits in the list header rather than the
                          // app bar.
                          PopupMenuButton<ChapterSort>(
                            icon: const Icon(Icons.sort, size: 20),
                            tooltip: 'Sort chapters',
                            initialValue: _chapterSort,
                            onSelected: (value) =>
                                setState(() => _chapterSort = value),
                            itemBuilder: (context) => [
                              for (final sort in ChapterSort.values)
                                _menuItem(
                                  context,
                                  sort,
                                  _chapterSort == sort
                                      ? Icons.check
                                      : Icons.sort,
                                  sort.label,
                                  checked: _chapterSort == sort,
                                ),
                            ],
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
                        spacing: Insets.sm,
                        runSpacing: Insets.xs,
                        children: ChapterFilter.values.map((filter) {
                          return FilterChip(
                            label: Text(filter.label),
                            selected: _chapterFilter == filter,
                            visualDensity: VisualDensity.compact,
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
                        (chapter) => _buildChapterRow(
                          key: ValueKey(chapter.id),
                          name: chapter.name,
                          read: chapter.read,
                          downloaded: chapter.downloaded,
                          selected:
                              _selecting &&
                              _selectedChapterIds.contains(chapter.id),
                          selectionArmed: _selecting,
                          onDownload: chapter.downloaded
                              ? null
                              : () => ref
                                    .read(downloadProvider.notifier)
                                    .downloadChapter(
                                      widget.novelId,
                                      chapter.id,
                                    ),
                          onTap: () {
                            if (_selecting) {
                              _toggleSelection(chapter.id);
                              return;
                            }
                            context.push(
                              '/reader/${widget.novelId}/${chapter.id}',
                            );
                          },
                          onLongPress: () {
                            if (_selecting) return;
                            unawaited(
                              _showChapterRowMenu(
                                context,
                                chapter,
                                filteredChapters,
                              ),
                            );
                          },
                        ),
                      ),
                    _HighlightsSection(novel: novel, chapters: sortedChapters),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),

            // Floating Play / Resume Button. Hidden while picking chapters:
            // it would sit on top of the selection bar.
            if (!_selecting)
              Positioned(
                right: Insets.lg,
                bottom: Insets.lg,
                child: FloatingActionButton.extended(
                  onPressed: () => _playFromStart(ref),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    'Resume',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),

            // Selection actions at the bottom, thumb-reachable.
            if (_selecting)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildSelectionBar(context),
              ),
          ],
        );
      },
    );
  }

  /// One chapter row. Reads as a dense scan list rather than a card: the
  /// previous ListTile showed only ~9 chapters per phone screen, each row
  /// spending 72dp on a 14px title.
  Widget _buildChapterRow({
    required Key key,
    required String name,
    required bool read,
    required bool downloaded,
    required bool selected,
    required bool selectionArmed,
    required VoidCallback? onDownload,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final compact = screenSizeOf(context).isCompact;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: compact ? Insets.xs : Insets.sm,
          ),
          child: Row(
            children: [
              // Selection checkbox replaces the read rule while picking, so
              // the two never compete for the same leading column.
              if (selectionArmed)
                Icon(
                  selected ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 20,
                  color: selected ? scheme.primary : scheme.outline,
                )
              else
                // Read state as a leading rule: scannable down the list
                // without spending a text column on the word "Available".
                Container(
                  width: 3,
                  height: compact ? 20 : 24,
                  decoration: BoxDecoration(
                    color: read ? scheme.outlineVariant : scheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    fontWeight: read ? FontWeight.w400 : FontWeight.w600,
                    color: read ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                ),
              ),
              // The per-row download button has no meaning mid-selection;
              // the bulk action covers it.
              if (!selectionArmed) ...[
                const SizedBox(width: Insets.sm),
                IconButton(
                  icon: Icon(
                    downloaded
                        ? Icons.download_done
                        : Icons.arrow_circle_down_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  tooltip: downloaded ? 'Downloaded' : 'Download chapter',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDownload,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One labelled action in the bottom selection bar.
class _BarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  const _BarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = enabled ? scheme.onSurfaceVariant : scheme.outline;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.all(Radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.sm,
            vertical: Insets.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: color, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small icon+label action for the novel header, sitting inline with the
/// title/author block instead of claiming a full-width row.
class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.all(Radii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.sm,
            vertical: Insets.xs,
          ),
          decoration: BoxDecoration(
            color: active
                ? scheme.primaryContainer.withValues(alpha: 0.4)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.all(Radii.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: Insets.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Popup item with a leading icon.
///
/// The label sits in an [Expanded] so it ellipsizes instead of forcing the
/// row wider than the popup route's clamped width. A plain `Row[Icon, Text]`
/// has no flexible child, so it overflowed by ~150px on every screen size.
PopupMenuItem<T> _menuItem<T>(
  BuildContext context,
  T value,
  IconData icon,
  String label, {
  bool checked = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  return PopupMenuItem<T>(
    value: value,
    child: Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: checked ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
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
