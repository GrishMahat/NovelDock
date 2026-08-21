import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/content/content_model.dart';
import '../../core/content/markdown/md_ast.dart';
import '../../core/content/markdown/md_parser.dart';
import '../../core/content/providers/content_provider.dart';
import '../../core/content/providers/navigation_provider.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../core/tts/tts_manager.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/max_width_box.dart';
import '../settings/pages/reader/reader_settings_state.dart';
import 'widgets/bookmark_sheet.dart';
import 'widgets/chapter_sidebar.dart';
import 'widgets/chapter_sheet.dart';
import 'widgets/reader_content_view.dart';
import 'widgets/reader_controls.dart';
import 'widgets/reader_settings_sheet.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterId;
  const ReaderScreen({
    super.key,
    required this.novelId,
    required this.chapterId,
  });

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _showControls = false;

  /// Chapter slider panel visibility (hover-driven on desktop).
  bool _sliderVisible = false;

  /// When pinned (Ctrl+L) the panel stays open regardless of mouse leave.
  bool _sliderPinned = false;
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  double _scrollProgress = 0.0;
  final Map<String, GlobalKey> _chunkKeys = {};
  double? _ttsScrollCeiling;
  int _settingsVersion = 0;

  /// Anchor autosave: last saved block index + throttle timestamp.
  int _lastSavedAnchorBlock = -1;
  DateTime _lastAnchorSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// Mirrored from the navigation state on every build so dispose() can save
  /// the anchor without touching ref or protected notifier state.
  int? _currentChapterId;

  /// Captured in initState so dispose() can save the reading position
  /// without touching `ref` (unsafe while unmounting).
  ReaderNavigationNotifier? _navigationNotifier;

  /// Block index -> TTS paragraph index for the chapter TTS last started on.
  /// Paragraphs are the TTS units, so a chapter with headings/blockquotes has
  /// more blocks than paragraphs; this map keeps highlighting aligned.
  Map<int, int> _blockToParagraph = const {};
  Map<int, int> _paragraphToBlock = const {};

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _scrollController.addListener(_onScroll);

    _navigationNotifier = ref.read(
      readerNavigationProvider(widget.novelId).notifier,
    );
    _navigationNotifier!.loadChapters(widget.chapterId);
  }

  @override
  void dispose() {
    _saveReadingAnchor();
    _scrollController.dispose();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Saves the resume anchor (visible content block) for the current chapter.
  /// Skipped in paged mode: the scroll controller has no clients there, and
  /// saving nothing must never overwrite a good anchor.
  void _saveReadingAnchor() {
    final notifier = _navigationNotifier;
    final chapterId = _currentChapterId;
    if (notifier == null || chapterId == null) return;
    // No clients in paged mode.
    if (!_scrollController.hasClients) return;
    final block = _firstVisibleBlockIndex(chapterId);
    if (block != null) notifier.saveReadingAnchor(chapterId, block);
  }

  /// Index of the first content block whose bottom edge is still below the
  /// viewport top, i.e. the block the reader is currently looking at.
  int? _firstVisibleBlockIndex(int chapterId) {
    if (!_scrollController.hasClients) return null;
    final scrollContext =
        _scrollController.position.context.notificationContext;
    final viewportBox = scrollContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null) return null;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;

    final prefix = '$chapterId-';
    final indices = <int>[];
    for (final key in _chunkKeys.keys) {
      if (!key.startsWith(prefix)) continue;
      final i = int.tryParse(key.substring(prefix.length));
      if (i != null) indices.add(i);
    }
    indices.sort();
    for (final i in indices) {
      final context = _chunkKeys['$prefix$i']?.currentContext;
      if (context == null) continue;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      if (box.localToGlobal(Offset.zero).dy + box.size.height > viewportTop) {
        return i;
      }
    }
    return null;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions || pos.maxScrollExtent <= 0) return;

    final progress = pos.pixels / pos.maxScrollExtent;
    setState(() => _scrollProgress = progress.clamp(0.0, 1.0));

    final nav = ref.read(readerNavigationProvider(widget.novelId));
    final chapter = nav.currentChapter;
    if (chapter == null) return;

    // Periodically persist the resume anchor while reading.
    _autosaveAnchor(chapter.id);
    // Follow the viewport across chapter boundaries (continuous mode).
    _scrollSpy(nav);

    final settings = ref.read(readerSettingsProvider);
    if (settings.scrollMode == 'continuous' && progress > 0.85) {
      final idx = nav.currentIndex;
      for (var i = 0; i < 5; i++) {
        final n = idx + 1 + i;
        if (n < nav.chapters.length) {
          ref.read(contentProvider.notifier).loadChapter(nav.chapters[n].id);
        }
      }
    }

    final ceiling = _ttsScrollCeiling;
    if (ceiling != null && settings.ttsAutoScroll) {
      final ttsState = ref.read(ttsManagerProvider);
      if (ttsState.isSpeaking && pos.pixels > ceiling + 1) {
        _scrollController.jumpTo(ceiling);
      }
    }
  }

  /// Throttled anchor persistence: saves when the visible block changes, at
  /// most every 5 seconds (dispose always force-saves).
  void _autosaveAnchor(int chapterId) {
    final block = _firstVisibleBlockIndex(chapterId);
    if (block == null || block == _lastSavedAnchorBlock) return;
    _lastSavedAnchorBlock = block;
    final now = DateTime.now();
    if (now.difference(_lastAnchorSave).inSeconds < 5) return;
    _lastAnchorSave = now;
    ref
        .read(readerNavigationProvider(widget.novelId).notifier)
        .saveReadingAnchor(chapterId, block);
  }

  /// Continuous mode only: detect which chapter the viewport is actually in
  /// by checking each chapter's first content block against the viewport top,
  /// then sync navigation state so history and read-marking follow reality.
  void _scrollSpy(ReaderNavigationState nav) {
    if (nav.chapters.isEmpty) return;
    final scrollContext =
        _scrollController.position.context.notificationContext;
    final viewportBox = scrollContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null) return;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    const threshold = 120.0;

    int detected = nav.currentIndex;
    // Forward: chapter starts at/above the viewport top have been passed.
    for (
      var i = nav.currentIndex;
      i < nav.chapters.length && i <= nav.currentIndex + 3;
      i++
    ) {
      final context = _chunkKeys['${nav.chapters[i].id}-0']?.currentContext;
      if (context == null) break;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) break;
      if (box.localToGlobal(Offset.zero).dy <= viewportTop + threshold) {
        detected = i;
      } else {
        break;
      }
    }
    // Backward: current chapter's start has dropped below the viewport.
    while (detected > 0) {
      final context =
          _chunkKeys['${nav.chapters[detected].id}-0']?.currentContext;
      if (context == null) break;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) break;
      if (box.localToGlobal(Offset.zero).dy > viewportTop + threshold) {
        detected--;
      } else {
        break;
      }
    }
    if (detected != nav.currentIndex) {
      ref
          .read(readerNavigationProvider(widget.novelId).notifier)
          .syncCurrentIndexFromScroll(detected);
    }
  }

  /// Scrolls the saved content block into view once it exists in the tree.
  ///
  /// ListView.builder only materializes visible items, so the target chunk
  /// does not exist while we sit at the top. We probe downward in viewport
  /// steps, letting batches build, until the target appears and we snap to
  /// it. If the target never appears (stale anchor, changed parsing), we
  /// land on the nearest already-built chunk of the same chapter instead of
  /// stranding the viewport in blank space.
  void _restoreAnchor(int block) {
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    final chapter = nav.currentChapter;
    if (chapter == null) return;

    final prefix = '${chapter.id}-';
    final key = '$prefix$block';

    var probe = 0.0;
    var stagnantFrames = 0;
    var lastMaxExtent = -1.0;

    /// Largest already-built block index of this chapter.
    int builtUpTo() {
      var maxBuilt = -1;
      for (final k in _chunkKeys.keys) {
        if (!k.startsWith(prefix)) continue;
        final i = int.tryParse(k.substring(prefix.length));
        if (i != null && i > maxBuilt) maxBuilt = i;
      }
      return maxBuilt;
    }

    void landOnNearest() {
      final maxBuilt = builtUpTo();
      if (maxBuilt < 0) return;

      // Prefer the closest built chunk at or below the target.
      for (var i = block.clamp(0, maxBuilt); i >= 0; i--) {
        final context = _chunkKeys['$prefix$i']?.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.08,
            duration: Duration.zero,
          );
          return;
        }
      }
    }

    void step(int attempt) {
      if (!mounted) return;

      if (!_scrollController.hasClients) {
        _retryFrame(step, attempt);
        return;
      }

      final context = _chunkKeys[key]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.08,
          duration: Duration.zero,
        );
        return;
      }

      // Target unreachable (never built): settle nearby instead of
      // wandering into blank space.
      if (attempt > 300 || stagnantFrames > 10) {
        landOnNearest();
        return;
      }

      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= lastMaxExtent) {
        stagnantFrames++;
      } else {
        stagnantFrames = 0;
        lastMaxExtent = maxExtent;
      }

      // Advance the probe by two viewport heights per frame.
      final viewport = _scrollController.position.viewportDimension;
      probe = (probe + viewport * 2).clamp(0.0, maxExtent);

      if (maxExtent > 0) _scrollController.jumpTo(probe);

      _retryFrame(step, attempt + 1);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => step(0));
  }

  void _retryFrame(void Function(int attempt) step, int attempt) {
    WidgetsBinding.instance.addPostFrameCallback((_) => step(attempt));
  }

  void _goToPreviousChapter() {
    ref
        .read(readerNavigationProvider(widget.novelId).notifier)
        .goToPreviousChapter();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _goToNextChapter() {
    ref
        .read(readerNavigationProvider(widget.novelId).notifier)
        .goToNextChapter();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _jumpToChapter(int index) {
    ref
        .read(readerNavigationProvider(widget.novelId).notifier)
        .jumpToChapter(index);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    // Reading intent: slide the panel away unless the user pinned it open.
    if (!_sliderPinned) setState(() => _sliderVisible = false);
  }

  void _handleTap(TapUpDetails details) {
    final settings = ref.read(readerSettingsProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final tapX = details.localPosition.dx;
    final third = screenWidth / 3;

    String action;
    if (tapX < third) {
      action = settings.leftTapAction;
    } else if (tapX > screenWidth - third) {
      action = settings.rightTapAction;
    } else {
      action = settings.centerTapAction;
    }

    switch (action) {
      case 'previous':
        _goToPreviousChapter();
        break;
      case 'next':
        _goToNextChapter();
        break;
      case 'menu':
        setState(() => _showControls = !_showControls);
        break;
    }
  }

  void _scrollToTtsHighlight(int lineIndex) {
    if (!_scrollController.hasClients) return;
    final settings = ref.read(readerSettingsProvider);
    if (!settings.ttsAutoScroll || settings.scrollMode == 'paged') return;

    final nav = ref.read(readerNavigationProvider(widget.novelId));
    final chapter = nav.currentChapter;
    if (chapter == null) return;

    final ttsState = ref.read(ttsManagerProvider);
    final blockIndex = _paragraphToBlock[ttsState.currentChunkIndex];
    if (blockIndex == null) return;
    final chunkKey = _chunkKeys['${chapter.id}-$blockIndex'];
    if (chunkKey?.currentContext != null) {
      Scrollable.ensureVisible(
        chunkKey!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        alignment: 0.25,
      );
    }
  }

  void _toggleTts() async {
    final ttsState = ref.read(ttsManagerProvider);
    if (ttsState.isSpeaking || ttsState.isPaused) {
      ref.read(ttsManagerProvider.notifier).stop();
      return;
    }

    final nav = ref.read(readerNavigationProvider(widget.novelId));
    final chapter = nav.currentChapter;
    if (chapter == null) return;

    final chapterContent = ref
        .read(contentProvider.notifier)
        .getChapter(chapter.id);
    if (chapterContent == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chapter not loaded yet')));
      return;
    }

    if (chapterContent.isPdf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TTS is not available for PDF chapters')),
      );
      return;
    }

    // Mark chapter as TTS-read when TTS starts
    await ref.read(chapterDaoProvider).markChapterAsTtsRead(chapter.id);

    final doc = MDParser.parse(chapterContent.data);
    final blockToParagraph = <int, int>{};
    final paragraphs = <String>[];
    for (var i = 0; i < doc.blocks.length; i++) {
      final block = doc.blocks[i];
      if (block is! ParagraphNode) continue;
      final text = block.children
          .whereType<TextNode>()
          .map((t) => t.text)
          .join();
      if (text.trim().isEmpty) continue;
      blockToParagraph[i] = paragraphs.length;
      paragraphs.add(text);
    }

    if (paragraphs.isEmpty) return;

    _blockToParagraph = blockToParagraph;
    _paragraphToBlock = {
      for (final e in blockToParagraph.entries) e.value: e.key,
    };

    final startParagraph = _firstVisibleParagraph(chapter.id, blockToParagraph);

    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(widget.novelId);
    ref
        .read(ttsManagerProvider.notifier)
        .startFromParagraphs(
          paragraphs,
          startParagraph: startParagraph,
          coverUrl: novel?.coverUrl,
          novelTitle: novel?.title,
          novelAuthor: novel?.author,
        );
  }

  /// Returns the TTS paragraph index whose text is the first visible text in
  /// the viewport. Used so TTS starts from where the user is looking instead
  /// of always from the top of the chapter.
  int _firstVisibleParagraph(int chapterId, Map<int, int> blockToParagraph) {
    if (blockToParagraph.isEmpty) return 0;
    if (!_scrollController.hasClients) return 0;

    final scrollContext =
        _scrollController.position.context.notificationContext;
    final viewportBox = scrollContext?.findRenderObject() as RenderBox?;
    final viewportTop = viewportBox?.localToGlobal(Offset.zero).dy ?? 0.0;

    // Find the block whose bottom edge is the first to cross the top of the
    // viewport. Blocks above it are fully scrolled out of view.
    final blockIndices = blockToParagraph.keys.toList()..sort();
    for (final blockIndex in blockIndices) {
      final key = _chunkKeys['$chapterId-$blockIndex'];
      final context = key?.currentContext;
      if (context == null) continue;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom > viewportTop) {
        return blockToParagraph[blockIndex]!;
      }
    }
    return 0;
  }

  void _autoAdvanceTts() async {
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    if (nav.currentIndex >= nav.chapters.length - 1) return;

    final currentChapter = nav.currentChapter;
    if (currentChapter != null) {
      // Mark current chapter as TTS-read
      await ref
          .read(chapterDaoProvider)
          .markChapterAsTtsRead(currentChapter.id);
    }

    _goToNextChapter();
    final nextChapter = ref
        .read(readerNavigationProvider(widget.novelId))
        .currentChapter;
    if (nextChapter == null) return;

    // Wait for chapter content to load
    await ref.read(contentProvider.notifier).loadChapter(nextChapter.id);
    final chapterContent = ref
        .read(contentProvider.notifier)
        .getChapter(nextChapter.id);
    if (chapterContent == null || chapterContent.isPdf) return;

    final doc = MDParser.parse(chapterContent.data);
    final blockToParagraph = <int, int>{};
    final paragraphs = <String>[];
    for (var i = 0; i < doc.blocks.length; i++) {
      final block = doc.blocks[i];
      if (block is! ParagraphNode) continue;
      final text = block.children
          .whereType<TextNode>()
          .map((t) => t.text)
          .join();
      if (text.trim().isEmpty) continue;
      blockToParagraph[i] = paragraphs.length;
      paragraphs.add(text);
    }
    if (paragraphs.isEmpty) return;

    _blockToParagraph = blockToParagraph;
    _paragraphToBlock = {
      for (final e in blockToParagraph.entries) e.value: e.key,
    };

    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(widget.novelId);
    ref
        .read(ttsManagerProvider.notifier)
        .startFromParagraphs(
          paragraphs,
          coverUrl: novel?.coverUrl,
          novelTitle: novel?.title,
          novelAuthor: novel?.author,
        );
  }

  void _addBookmark() async {
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    final chapter = nav.currentChapter;
    if (chapter == null) return;

    if (!context.mounted) return;
    final note = await showAddBookmarkDialog(
      context,
      chapterName: chapter.name,
    );
    if (note == null) return;

    final bookmarkDao = ref.read(bookmarkDaoProvider);
    await bookmarkDao.addBookmark(
      BookmarksCompanion(
        novelId: Value(widget.novelId),
        chapterId: Value(chapter.id),
        position: Value(_scrollProgress.toStringAsFixed(4)),
        note: note.isNotEmpty ? Value(note) : const Value.absent(),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bookmarked: ${chapter.name}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showBookmarks() async {
    final bookmarkDao = ref.read(bookmarkDaoProvider);
    final bookmarks = await bookmarkDao.getBookmarksForNovel(widget.novelId);
    if (!mounted) return;

    if (bookmarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bookmarks for this novel')),
      );
      return;
    }

    final nav = ref.read(readerNavigationProvider(widget.novelId));
    showBookmarkSheet(
      context: context,
      bookmarks: bookmarks,
      chapters: nav.chapters,
      onTapBookmark: (chapterIndex, pos) {
        _jumpToChapter(chapterIndex);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients &&
              _scrollController.position.hasContentDimensions) {
            _scrollController.jumpTo(
              pos * _scrollController.position.maxScrollExtent,
            );
          }
        });
      },
      onDeleteBookmark: (bookmarkId) async {
        await bookmarkDao.removeBookmark(bookmarkId);
        if (mounted) _showBookmarks();
      },
    );
  }

  void _showChapterList() {
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    showChapterListSheet(
      context: context,
      chapters: nav.chapters,
      currentIndex: nav.currentIndex,
      onJumpToChapter: _jumpToChapter,
    );
  }

  void _toggleSliderPinned() {
    setState(() {
      _sliderPinned = !_sliderPinned;
      _sliderVisible = _sliderPinned || _sliderVisible;
    });
  }

  void _hideSlider() {
    if (_sliderPinned || !_sliderVisible) return;
    setState(() => _sliderVisible = false);
  }

  void _showSettingsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) =>
            ReaderSettingsSheet(scrollController: scrollController),
      ),
    );
  }

  Map<int, ChapterContent> _buildContentMap(ContentState state) {
    return Map.fromEntries(
      state.chapters.entries
          .where((e) => e.value is AsyncData<ChapterContent>)
          .map(
            (e) =>
                MapEntry(e.key, (e.value as AsyncData<ChapterContent>).value),
          ),
    );
  }

  Map<int, String> _buildErrorMap(ContentState state) {
    return Map.fromEntries(
      state.chapters.entries
          .where((e) => e.value is AsyncError<ChapterContent>)
          .map(
            (e) => MapEntry(
              e.key,
              (e.value as AsyncError<ChapterContent>).error.toString(),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(readerNavigationProvider(widget.novelId));
    final settings = ref.watch(readerSettingsProvider);
    final ttsState = ref.watch(ttsManagerProvider);
    final ttsActive = ttsState.isSpeaking || ttsState.isPaused;
    final contentState = ref.watch(contentProvider);

    final currentChapter = nav.currentChapter;
    _currentChapterId = currentChapter?.id;

    ref.listen(ttsManagerProvider, (prev, next) {
      if (next.isSpeaking && prev?.currentLineIndex != next.currentLineIndex) {
        _scrollToTtsHighlight(next.currentLineIndex);
      }
      if ((prev?.isSpeaking == true) && !next.isSpeaking) {
        _ttsScrollCeiling = null;
        // Only advance when the chapter finished playing on its own; a user
        // stop or a fatal error must not silently jump to the next chapter.
        if (next.completedNaturally &&
            settings.ttsAutoAdvance &&
            nav.currentIndex < nav.chapters.length - 1) {
          _autoAdvanceTts();
        }
      }
    });

    // Restore the reading anchor once the chapter content is built
    ref.listen<int?>(
      readerNavigationProvider(
        widget.novelId,
      ).select((s) => s.restoredBlockIndex),
      (prev, block) {
        if (block == null) return;
        _restoreAnchor(block);
        ref
            .read(readerNavigationProvider(widget.novelId).notifier)
            .clearRestoredBlockIndex();
      },
    );

    _settingsVersion++;

    final isDesktop =
        Platform.isLinux || Platform.isWindows || Platform.isMacOS;

    final contentCache = _buildContentMap(contentState);
    final errorCache = _buildErrorMap(contentState);

    final readerBody = nav.isLoading
        ? const Center(child: CircularProgressIndicator())
        : nav.error != null
        ? _buildError()
        : settings.scrollMode == 'paged'
        ? buildPagedContent(
            context: context,
            settings: settings,
            chapters: nav.chapters,
            currentIndex: nav.currentIndex,
            contentCache: contentCache,
            errorCache: errorCache,
            pageController: _pageController,
            onPageChanged: (index) {
              ref
                  .read(readerNavigationProvider(widget.novelId).notifier)
                  .jumpToChapter(index);
            },
            loadChapter: (chapterId) =>
                ref.read(contentProvider.notifier).loadChapter(chapterId),
            goToPreviousChapter: _goToPreviousChapter,
            goToNextChapter: _goToNextChapter,
            chunkKeys: _chunkKeys,
            settingsVersion: _settingsVersion,
            ttsState: ttsState,
            blockToParagraph: _blockToParagraph,
          )
        : buildContinuousContent(
            context: context,
            settings: settings,
            chapters: nav.chapters,
            currentIndex: nav.currentIndex,
            contentCache: contentCache,
            errorCache: errorCache,
            scrollController: _scrollController,
            loadChapter: (chapterId) =>
                ref.read(contentProvider.notifier).loadChapter(chapterId),
            chunkKeys: _chunkKeys,
            settingsVersion: _settingsVersion,
            ttsState: ttsState,
            blockToParagraph: _blockToParagraph,
          );

    return Scaffold(
      backgroundColor: settings.bgColor,
      body: isDesktop
          ? CallbackShortcuts(
              bindings: {
                SingleActivator(LogicalKeyboardKey.arrowLeft):
                    _goToPreviousChapter,
                SingleActivator(LogicalKeyboardKey.arrowRight):
                    _goToNextChapter,
                SingleActivator(LogicalKeyboardKey.escape): () =>
                    Navigator.pop(context),
                SingleActivator(LogicalKeyboardKey.space): () {
                  setState(() => _showControls = !_showControls);
                },
                SingleActivator(LogicalKeyboardKey.keyL, control: true):
                    _toggleSliderPinned,
              },
              child: Focus(
                autofocus: true,
                child: Stack(
                  children: [
                    GestureDetector(
                      onTapUp: (details) {
                        if (ttsActive) return;
                        _handleTap(details);
                      },
                      child: Stack(
                        children: [
                          MaxWidthBox(
                            maxWidth: Desktop.readerMaxWidth,
                            padding: EdgeInsets.zero,
                            child: readerBody,
                          ),
                          ..._overlayWidgets(
                            settings,
                            ttsState,
                            ttsActive,
                            currentChapter,
                          ),
                        ],
                      ),
                    ),
                    if (nav.chapters.isNotEmpty) ...[
                      // Invisible hover zone on the right edge reveals the slider.
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        width: Desktop.readerEdgeZoneWidth,
                        child: MouseRegion(
                          opaque: false,
                          onEnter: (_) {
                            if (!_sliderVisible) {
                              setState(() => _sliderVisible = true);
                            }
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                      // Floating chapter slider panel.
                      AnimatedPositioned(
                        duration: Motion.base,
                        curve: Curves.easeOutCubic,
                        top: 0,
                        bottom: 0,
                        right: _sliderVisible
                            ? 0
                            : -(Desktop.readerSidebarWidth + Insets.sm),
                        child: MouseRegion(
                          onExit: (_) => _hideSlider(),
                          child: ChapterSidebar(
                            chapters: nav.chapters,
                            currentIndex: nav.currentIndex,
                            settings: settings,
                            onJumpToChapter: _jumpToChapter,
                            onClose: () => setState(() {
                              _sliderVisible = false;
                              _sliderPinned = false;
                            }),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : GestureDetector(
              onTapUp: (details) {
                if (ttsActive) return;
                _handleTap(details);
              },
              child: Stack(
                children: [
                  readerBody,
                  ..._overlayWidgets(
                    settings,
                    ttsState,
                    ttsActive,
                    currentChapter,
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _overlayWidgets(
    ReaderSettings settings,
    TtsManagerState ttsState,
    bool ttsActive,
    Chapter? currentChapter,
  ) {
    return [
      if (_showControls && !ttsActive)
        buildReaderTopBar(
          context: context,
          settings: settings,
          chapterName: currentChapter?.name ?? 'Chapter',
          onBack: () => Navigator.pop(context),
          onAddBookmark: _addBookmark,
          onShowBookmarks: _showBookmarks,
        ),
      if (_showControls && !ttsActive)
        buildReaderBottomBar(
          settings: settings,
          onPrevious: _goToPreviousChapter,
          onNext: _goToNextChapter,
          onToggleTts: _toggleTts,
          onShowChapterList: _showChapterList,
          onSettings: _showSettingsDialog,
        ),
      if (_showControls && !ttsActive)
        buildReaderProgressBar(_scrollProgress, settings),
      if (ttsActive)
        buildTtsFloatingPlayer(
          settings: settings,
          ttsState: ttsState,
          onSkipBack: () =>
              ref.read(ttsManagerProvider.notifier).skipBackward(),
          onTogglePause: () =>
              ref.read(ttsManagerProvider.notifier).togglePause(),
          onStop: () => ref.read(ttsManagerProvider.notifier).stop(),
          onSkipNext: () => ref.read(ttsManagerProvider.notifier).skipForward(),
        ),
    ];
  }

  Widget _buildError() {
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            nav.error!,
            style: const TextStyle(color: AppTheme.kReaderTextDefault),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              ref
                  .read(readerNavigationProvider(widget.novelId).notifier)
                  .loadChapters(widget.chapterId);
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
