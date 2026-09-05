import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  int? _lastAutoScrolledParagraph;
  Future<void>? _autoScrollFuture;
  bool _restoringTtsScroll = false;
  int _settingsVersion = 0;
  double _lastScrollPixels = 0.0;

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
  ProviderSubscription<TtsManagerState>? _ttsSubscription;
  bool _autoAdvancingTts = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // The book is open: keep the screen on until the reader closes.
    try {
      WakelockPlus.enable();
    } catch (e) {
      debugPrint('WakelockPlus unavailable: $e');
    }
    _scrollController.addListener(_onScroll);

    _navigationNotifier = ref.read(
      readerNavigationProvider(widget.novelId).notifier,
    );
    _navigationNotifier!.loadChapters(widget.chapterId);
    _ttsSubscription = ref.listenManual<TtsManagerState>(
      ttsManagerProvider,
      (prev, next) => _onTtsStateChanged(prev, next),
    );
  }

  @override
  void dispose() {
    _ttsSubscription?.close();
    _saveReadingAnchor();
    _scrollController.dispose();
    _pageController.dispose();
    try {
      WakelockPlus.disable();
    } catch (e) {
      debugPrint('WakelockPlus unavailable: $e');
    }
    // The reader forced portrait; give the rest of the app its freedom back.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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

    // Reading started: get the chrome out of the way.
    final scrollDelta = (pos.pixels - _lastScrollPixels).abs();
    _lastScrollPixels = pos.pixels;
    if (_showControls && scrollDelta > 28) {
      final tts = ref.read(ttsManagerProvider);
      if (!tts.isSpeaking && !tts.isPaused) {
        setState(() => _showControls = false);
      }
    }

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
    final ttsState = ref.read(ttsManagerProvider);
    final lockScroll =
        settings.ttsAutoScroll &&
        settings.ttsScrollLock &&
        ttsState.isSpeaking &&
        !_restoringTtsScroll;
    if (lockScroll && ceiling != null && (pos.pixels - ceiling).abs() > 1) {
      _restoreLockedTtsScroll(ceiling);
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

  /// Scrolls the saved content block into view.
  ///
  /// Continuous mode merges every chapter into one lazy list padded with
  /// fixed-height placeholders, so blind scrolling wanders into blank
  /// territory. Instead: measure the average real height of built blocks,
  /// jump to the estimated offset of the target, let the cache extent
  /// materialize around it, then snap precisely. A couple of refinement
  /// hops converge because paragraph heights are fairly uniform.
  void _restoreAnchor(int block) {
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    final chapter = nav.currentChapter;
    if (chapter == null) return;

    final prefix = '${chapter.id}-';
    final key = '$prefix$block';

    var attempts = 0;
    var lastOffset = -1.0;
    var stableFrames = 0;

    /// Average rendered height of this chapter's built blocks.
    double avgBuiltHeight() {
      var total = 0.0;
      var count = 0;
      for (final k in _chunkKeys.keys) {
        if (!k.startsWith(prefix)) continue;
        final box =
            _chunkKeys[k]?.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize || box.size.height <= 0) continue;
        total += box.size.height;
        count++;
      }
      return count == 0 ? 0.0 : total / count;
    }

    /// Largest built block index of this chapter.
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

    void step() {
      if (!mounted) return;

      if (!_scrollController.hasClients) {
        _retryFrame(step);
        return;
      }

      // Target built? Snap precisely and stop.
      final context = _chunkKeys[key]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.08,
          duration: Duration.zero,
        );
        return;
      }

      // Give up gracefully: settle on the closest built block.
      if (attempts++ > 90) {
        landOnNearest();
        return;
      }

      final avg = avgBuiltHeight();
      if (avg <= 0) {
        // Nothing measured yet; wait for the first batches to build.
        _retryFrame(step);
        return;
      }

      final maxExtent = _scrollController.position.maxScrollExtent;
      final estimate = (avg * block).clamp(0.0, maxExtent);

      if ((estimate - lastOffset).abs() < 24) {
        // Estimate stopped moving but the target still isn't built:
        // it likely does not exist (stale anchor). Settle nearby.
        if (++stableFrames >= 3) {
          landOnNearest();
          return;
        }
      } else {
        stableFrames = 0;
      }
      lastOffset = estimate;

      _scrollController.jumpTo(estimate);
      _retryFrame(step);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => step());
  }

  void _retryFrame(void Function() step) {
    WidgetsBinding.instance.addPostFrameCallback((_) => step());
  }

  void _scrollByPages(double pages) {
    if (!_scrollController.hasClients) return;
    final target =
        (_scrollController.offset +
                pages * _scrollController.position.viewportDimension * 0.85)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToPreviousChapter() {
    final settings = ref.read(readerSettingsProvider);
    if (settings.scrollMode == 'paged') {
      ref
          .read(readerNavigationProvider(widget.novelId).notifier)
          .goToPreviousChapter();
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } else {
      final nav = ref.read(readerNavigationProvider(widget.novelId));
      if (nav.currentIndex > 0) {
        final prevChapter = nav.chapters[nav.currentIndex - 1];
        final context = _chunkKeys['${prevChapter.id}-0']?.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          ref
              .read(readerNavigationProvider(widget.novelId).notifier)
              .goToPreviousChapter();
        }
      }
    }
  }

  void _goToNextChapter() {
    final settings = ref.read(readerSettingsProvider);
    if (settings.scrollMode == 'paged') {
      ref
          .read(readerNavigationProvider(widget.novelId).notifier)
          .goToNextChapter();
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } else {
      final nav = ref.read(readerNavigationProvider(widget.novelId));
      if (nav.currentIndex < nav.chapters.length - 1) {
        final nextChapter = nav.chapters[nav.currentIndex + 1];
        final context = _chunkKeys['${nextChapter.id}-0']?.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          ref
              .read(readerNavigationProvider(widget.novelId).notifier)
              .goToNextChapter();
        }
      }
    }
  }

  void _jumpToChapter(int index) {
    final settings = ref.read(readerSettingsProvider);
    if (settings.scrollMode == 'paged') {
      ref
          .read(readerNavigationProvider(widget.novelId).notifier)
          .jumpToChapter(index);
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } else {
      final nav = ref.read(readerNavigationProvider(widget.novelId));
      if (index >= 0 && index < nav.chapters.length) {
        final chapter = nav.chapters[index];
        final context = _chunkKeys['${chapter.id}-0']?.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          ref
              .read(readerNavigationProvider(widget.novelId).notifier)
              .jumpToChapter(index);
        }
      }
    }
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

  void _scrollToTtsHighlight(int lineIndex, {int attempt = 0}) {
    if (!_scrollController.hasClients) return;
    if (_autoScrollFuture != null) return;
    final settings = ref.read(readerSettingsProvider);
    if (!settings.ttsAutoScroll || settings.scrollMode == 'paged') return;

    final nav = ref.read(readerNavigationProvider(widget.novelId));
    final chapter = nav.currentChapter;
    if (chapter == null) return;

    final ttsState = ref.read(ttsManagerProvider);
    final paragraph = ttsState.currentChunkIndex;
    if (_lastAutoScrolledParagraph == paragraph) return;
    final blockIndex = _paragraphToBlock[paragraph];
    if (blockIndex == null) return;
    final targetContext =
        _chunkKeys['${chapter.id}-$blockIndex']?.currentContext;
    if (targetContext == null) {
      if (attempt < 3) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToTtsHighlight(lineIndex, attempt: attempt + 1),
        );
      }
      return;
    }

    _lastAutoScrolledParagraph = paragraph;
    _autoScrollFuture =
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.22,
        ).whenComplete(() {
          _autoScrollFuture = null;
          if (_scrollController.hasClients) {
            _ttsScrollCeiling = _scrollController.offset;
          }
        });
  }

  void _restoreLockedTtsScroll(double ceiling) {
    if (_restoringTtsScroll || !_scrollController.hasClients) return;
    _restoringTtsScroll = true;
    _autoScrollFuture = _scrollController
        .animateTo(
          ceiling.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          _restoringTtsScroll = false;
          _autoScrollFuture = null;
        });
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
    final viewportBottom =
        viewportTop + _scrollController.position.viewportDimension;

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
      debugPrint(
        'Block $blockIndex: top=$top, bottom=$bottom, viewportTop=$viewportTop, viewportBottom=$viewportBottom',
      );
      if (bottom > viewportTop && top < viewportBottom) {
        return blockToParagraph[blockIndex]!;
      }
    }
    // If the target is outside the currently built cache, use scroll geometry
    // as a stable fallback instead of silently restarting at paragraph zero.
    final extent = _scrollController.position.maxScrollExtent;
    if (extent <= 0) return 0;
    final ratio = (_scrollController.offset / extent).clamp(0.0, 1.0);
    final fallback = (ratio * (blockToParagraph.length - 1)).round();
    return fallback.clamp(0, blockToParagraph.length - 1);
  }

  Future<void> _autoAdvanceTts() async {
    if (_autoAdvancingTts) return;
    _autoAdvancingTts = true;
    try {
      final nav = ref.read(readerNavigationProvider(widget.novelId));
      final settings = ref.read(readerSettingsProvider);
      if (!settings.ttsAutoAdvance ||
          nav.currentIndex >= nav.chapters.length - 1) {
        return;
      }

      final currentChapter = nav.currentChapter;
      final nextChapter = nav.chapters[nav.currentIndex + 1];

      // Scroll to the next chapter if possible (before any async gap)
      final nextContext = _chunkKeys['${nextChapter.id}-0']?.currentContext;
      if (nextContext != null) {
        Scrollable.ensureVisible(
          nextContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _goToNextChapter();
      }

      if (currentChapter != null) {
        await ref
            .read(chapterDaoProvider)
            .markChapterAsTtsRead(currentChapter.id);
      }

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
      await ref
          .read(ttsManagerProvider.notifier)
          .startFromParagraphs(
            paragraphs,
            coverUrl: novel?.coverUrl,
            novelTitle: novel?.title,
            novelAuthor: novel?.author,
          );
    } finally {
      _autoAdvancingTts = false;
    }
  }

  void _onTtsStateChanged(TtsManagerState? prev, TtsManagerState next) {
    debugPrint(
      'TTS State Changed: isSpeaking=${next.isSpeaking}, prevLine=${prev?.currentLineIndex}, nextLine=${next.currentLineIndex}',
    );
    if (next.isSpeaking && prev?.currentLineIndex != next.currentLineIndex) {
      _scrollToTtsHighlight(next.currentLineIndex);
    }
    if ((prev?.isSpeaking == true) && !next.isSpeaking) {
      _ttsScrollCeiling = null;
      _lastAutoScrolledParagraph = null;
      _autoScrollFuture = null;
      if (next.completedNaturally) {
        _autoAdvanceTts();
      }
    }
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
        ? _ReaderLoadingSkeleton(settings: settings)
        : nav.error != null
        ? _buildError(settings)
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
                SingleActivator(LogicalKeyboardKey.pageUp): () =>
                    _scrollByPages(-1),
                SingleActivator(LogicalKeyboardKey.pageDown): () =>
                    _scrollByPages(1),
                SingleActivator(LogicalKeyboardKey.home): () {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(0);
                  }
                },
                SingleActivator(LogicalKeyboardKey.end): () {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
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
                            nav.chapters.isEmpty
                                ? null
                                : '${nav.currentIndex + 1} / ${nav.chapters.length}',
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
                    nav.chapters.isEmpty
                        ? null
                        : '${nav.currentIndex + 1} / ${nav.chapters.length}',
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
    String? positionLabel,
  ) {
    return [
      if (_showControls && !ttsActive)
        buildReaderTopBar(
          context: context,
          settings: settings,
          chapterName: currentChapter?.name ?? 'Chapter',
          positionLabel: positionLabel,
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

  Widget _buildError(ReaderSettings settings) {
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppTheme.kReaderError,
            ),
            const SizedBox(height: Insets.lg),
            Text(
              nav.error!,
              style: TextStyle(color: settings.textColor, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.lg),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: settings.textColor.withValues(alpha: 0.12),
                foregroundColor: settings.textColor,
              ),
              onPressed: () {
                ref
                    .read(readerNavigationProvider(widget.novelId).notifier)
                    .loadChapters(widget.chapterId);
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prose-shaped placeholder shown while the chapter list first loads.
/// Shimmers in the active reader palette instead of the app scheme so it
/// sits correctly on any reader background.
class _ReaderLoadingSkeleton extends StatelessWidget {
  final ReaderSettings settings;
  const _ReaderLoadingSkeleton({required this.settings});

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final lineHeight = s.fontSize * 0.72;
    return Shimmer.fromColors(
      baseColor: s.textColor.withValues(alpha: 0.08),
      highlightColor: s.textColor.withValues(alpha: 0.18),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: s.paddingH,
          vertical: s.paddingV,
        ),
        itemCount: 14,
        itemBuilder: (_, paragraph) => Padding(
          padding: EdgeInsets.only(bottom: s.paragraphSpacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var line = 0; line < 4; line++)
                Container(
                  height: lineHeight,
                  margin: EdgeInsets.only(bottom: lineHeight * 0.45),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: s.textColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(lineHeight / 2),
                  ),
                ),
              FractionallySizedBox(
                widthFactor: 0.55 + ((paragraph * 37) % 30) / 100,
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  height: lineHeight,
                  decoration: BoxDecoration(
                    color: s.textColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(lineHeight / 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
