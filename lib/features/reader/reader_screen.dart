import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../core/providers/engine.dart';
import '../../core/providers/registry.dart';
import '../../core/network/client.dart';
import '../../core/utils/html_preprocessor.dart';
import '../../core/utils/logger.dart';
import '../../theme/app_theme.dart';
import '../../core/tts/tts_manager.dart';
import '../../core/tts/tts_highlighter.dart';
import '../settings/pages/reader_settings_page.dart';

const _tag = 'Reader';

/// A loaded chapter with its HTML content
class _LoadedChapter {
  final Chapter chapter;
  final String html;
  _LoadedChapter({required this.chapter, required this.html});
}

class ReaderScreen extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterId;
  const ReaderScreen({super.key, required this.novelId, required this.chapterId});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _showControls = false;
  bool _isLoading = true;
  String? _error;

  // Chapter management
  List<Chapter> _chapters = [];
  int _currentIndex = 0;
  final Map<int, _LoadedChapter> _chapterCache = {};
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  double _scrollProgress = 0.0;

  // GlobalKeys for each chapter content widget, so we can read their actual
  // rendered RenderBox positions instead of estimating from HTML length.
  final Map<int, GlobalKey> _chapterContentKeys = {};

  // Maximum scroll position the user is allowed to reach while TTS is active
  // and auto-scroll is enabled. Updated each time TTS advances a sentence.
  // null = no ceiling (TTS not active or auto-scroll off).
  double? _ttsScrollCeiling;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _scrollController.addListener(_onScroll);
    _loadChapters();
  }

  @override
  void dispose() {
    _saveReadingPosition();
    _scrollController.dispose();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _saveReadingPosition() {
    if (_chapters.isEmpty || _currentIndex >= _chapters.length) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final progress = pos.hasContentDimensions && pos.maxScrollExtent > 0
        ? pos.pixels / pos.maxScrollExtent
        : 0.0;

    final historyDao = ref.read(historyDaoProvider);
    historyDao.addHistoryEntry(ReadingHistoryCompanion(
      novelId: Value(widget.novelId),
      chapterId: Value(_chapters[_currentIndex].id),
      readAt: Value(DateTime.now().millisecondsSinceEpoch),
      scrollPosition: Value(progress),
    ));
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions || pos.maxScrollExtent <= 0) return;

    final progress = pos.pixels / pos.maxScrollExtent;
    setState(() => _scrollProgress = progress.clamp(0.0, 1.0));

    // Auto-load next chapter when near bottom (continuous mode)
    final settings = ref.read(readerSettingsProvider);
    if (settings.scrollMode == 'continuous' && progress > 0.9) {
      _loadNextChapter();
    }

    // TTS scroll ceiling: when auto-scroll is on and TTS is active,
    // prevent the user from scrolling forward past the current sentence.
    final ceiling = _ttsScrollCeiling;
    if (ceiling != null && settings.ttsAutoScroll) {
      final ttsState = ref.read(ttsManagerProvider);
      if (ttsState.isSpeaking && pos.pixels > ceiling + 1) {
        // Snap back to the ceiling without animation (feels like a natural stop).
        _scrollController.jumpTo(ceiling);
      }
    }
  }

  // ─── Chapter Loading ──────────────────────────────────────

  Future<void> _loadChapters() async {
    final chapterDao = ref.read(chapterDaoProvider);
    _chapters = await chapterDao.getChaptersForNovel(widget.novelId);
    _currentIndex = _chapters.indexWhere((c) => c.id == widget.chapterId);
    if (_currentIndex < 0) _currentIndex = 0;

    Log.i(_tag, 'Loaded ${_chapters.length} chapters, starting at index $_currentIndex');

    // Save reading history
    _saveHistory();

    // Check if this is an EPUB (local file)
    final isEpub = _chapters.isNotEmpty && _chapters.first.url.startsWith('epub://');

    if (isEpub) {
      // Load ALL EPUB chapters at once (they're from a local file, fast)
      for (var i = 0; i < _chapters.length; i++) {
        await _loadChapter(i);
      }
    } else {
      // Online: load current + next
      await _loadChapter(_currentIndex);
      final settings = ref.read(readerSettingsProvider);
      if (settings.scrollMode == 'continuous' && _currentIndex < _chapters.length - 1) {
        _loadChapter(_currentIndex + 1);
      }
    }

    setState(() => _isLoading = false);

    // Restore scroll position from history
    _restoreReadingPosition();
  }

  void _restoreReadingPosition() async {
    final historyDao = ref.read(historyDaoProvider);
    final latest = await historyDao.getLatestHistoryForNovel(widget.novelId);
    if (latest == null || latest.scrollPosition == null) return;
    if (latest.chapterId != widget.chapterId) return; // different chapter

    final position = latest.scrollPosition!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        _scrollController.jumpTo(position * maxScroll);
      }
    });
  }

  void _saveHistory() async {
    if (_chapters.isEmpty) return;
    final chapter = _chapters[_currentIndex];
    final historyDao = ref.read(historyDaoProvider);
    await historyDao.addHistoryEntry(ReadingHistoryCompanion(
      novelId: Value(widget.novelId),
      chapterId: Value(chapter.id),
      readAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
    Log.i(_tag, 'Saved history: novel=${widget.novelId}, chapter=${chapter.id}');
  }

  void _addBookmark() async {
    if (_chapters.isEmpty) return;
    final chapter = _chapters[_currentIndex];
    final bookmarkDao = ref.read(bookmarkDaoProvider);

    // Get current scroll position as percentage
    double position = 0.0;
    if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
      position = _scrollController.position.pixels / _scrollController.position.maxScrollExtent;
    }

    await bookmarkDao.addBookmark(BookmarksCompanion(
      novelId: Value(widget.novelId),
      chapterId: Value(chapter.id),
      position: Value(position.toStringAsFixed(4)),
      createdAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));

    Log.i(_tag, 'Bookmarked: novel=${widget.novelId}, chapter=${chapter.id}, pos=$position');

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

    if (!context.mounted) return;

    if (bookmarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bookmarks for this novel')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.4,
        maxChildSize: 0.7,
        minChildSize: 0.2,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Bookmarks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: bookmarks.length,
                itemBuilder: (context, index) {
                  final bm = bookmarks[index];
                  final chapter = _chapters.firstWhere(
                    (c) => c.id == bm.chapterId,
                    orElse: () => _chapters.first,
                  );
                  final time = DateTime.fromMillisecondsSinceEpoch(bm.createdAt)
                      .toLocal().toString().split(' ')[1].substring(0, 5);

                  return ListTile(
                    leading: const Icon(Icons.bookmark, color: AppTheme.kPrimary),
                    title: Text(chapter.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Position: ${(double.tryParse(bm.position ?? '0') ?? 0 * 100).round()}% · $time',
                        style: const TextStyle(fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        await bookmarkDao.removeBookmark(bm.id);
                        if (context.mounted) {
                          Navigator.pop(context);
                          _showBookmarks();
                        }
                      },
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      // Jump to chapter
                      final chIdx = _chapters.indexWhere((c) => c.id == bm.chapterId);
                      if (chIdx >= 0) {
                        _jumpToChapter(chIdx);
                        // Scroll to position
                        final pos = double.tryParse(bm.position ?? '0') ?? 0;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
                            _scrollController.jumpTo(pos * _scrollController.position.maxScrollExtent);
                          }
                        });
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    if (_chapterCache.containsKey(_chapters[index].id)) return;

    final chapter = _chapters[index];
    Log.i(_tag, 'Loading chapter ${index + 1}: ${chapter.name}');

    try {
      if (chapter.url.startsWith('epub://')) {
        await _loadEpubChapter(chapter, index);
      } else if (chapter.url.startsWith('pdf://')) {
        await _loadPdfChapter(chapter, index);
      } else {
        await _loadRemoteChapter(chapter, index);
      }
    } catch (e) {
      Log.e(_tag, 'Failed to load chapter ${index + 1}', e);
    }
  }

  Future<void> _loadEpubChapter(Chapter chapter, int index) async {
    final url = chapter.url;
    final filePath = url.replaceFirst('epub://', '').split('#').first;

    Log.i(_tag, 'Loading EPUB chapter from: $filePath');

    final file = File(filePath);
    if (!await file.exists()) {
      Log.e(_tag, 'EPUB file not found: $filePath');
      return;
    }

    final bytes = await file.readAsBytes();
    final book = await EpubReader.readBook(bytes);

    if (book.Chapters == null || book.Chapters!.isEmpty) {
      Log.e(_tag, 'No chapters in EPUB');
      return;
    }

    // Use index to match chapter (more reliable than title matching)
    final chIndex = index.clamp(0, book.Chapters!.length - 1);
    final ch = book.Chapters![chIndex];
    final html = ch.HtmlContent ?? '';
    final cleanHtml = HtmlPreprocessor.clean(html);
    _chapterCache[chapter.id] = _LoadedChapter(chapter: chapter, html: cleanHtml);
    Log.ok(_tag, 'EPUB chapter ${chIndex + 1} loaded: ${cleanHtml.length} chars');
    setState(() {});
  }

  Future<void> _loadPdfChapter(Chapter chapter, int index) async {
    // PDF chapters are rendered as page images, store the file path for PdfView
    final url = chapter.url;
    final filePath = url.replaceFirst('pdf://', '').split('#').first;

    Log.i(_tag, 'Loading PDF page from: $filePath');

    final file = File(filePath);
    if (!await file.exists()) {
      Log.e(_tag, 'PDF file not found: $filePath');
      return;
    }

    // Store a marker so the UI knows to render with PdfView
    _chapterCache[chapter.id] = _LoadedChapter(
      chapter: chapter,
      html: 'PDF:$filePath',
    );
    Log.ok(_tag, 'PDF chapter ${index + 1} marked for PDF rendering');
    setState(() {});
  }

  Future<void> _loadRemoteChapter(Chapter chapter, int index) async {
    try {
      final registry = await ref.read(registryManagerProvider.future);
      final engine = ref.read(providerEngineProvider);
      final dio = await ref.read(dioProvider.future);

      final novelDao = ref.read(novelDaoProvider);
      final novel = await novelDao.getNovelById(widget.novelId);
      if (novel == null) return;

      final jsSource = await registry.loadCachedProviderJs(novel.providerId);
      if (jsSource == null) {
        Log.w(_tag, 'No provider for ${novel.providerId}');
        return;
      }

      final instance = await engine.loadProvider(jsSource);
      final contentUrl = await instance.getChapterContentUrl(chapter.url);
      if (contentUrl == null) return;

      final response = await dio.get(contentUrl);
      final html = response.data.toString();
      final content = await instance.parseChapterContent(html);

      if (content != null) {
        final cleanHtml = HtmlPreprocessor.clean(content.html);
        _chapterCache[chapter.id] = _LoadedChapter(chapter: chapter, html: cleanHtml);
        Log.ok(_tag, 'Chapter loaded: ${cleanHtml.length} chars');
        setState(() {});
      }
    } catch (e) {
      Log.e(_tag, 'Failed to load chapter', e);
    }
  }

  Future<void> _loadNextChapter() async {
    if (_currentIndex < _chapters.length - 1) {
      await _loadChapter(_currentIndex + 1);
    }
  }

  // ─── Navigation ───────────────────────────────────────────

  void _goToPreviousChapter() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _loadChapter(_currentIndex);
      if (_currentIndex > 0) _loadChapter(_currentIndex - 1);
    }
  }

  void _goToNextChapter() {
    if (_currentIndex < _chapters.length - 1) {
      setState(() => _currentIndex++);
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _loadChapter(_currentIndex);
      if (_currentIndex < _chapters.length - 1) _loadChapter(_currentIndex + 1);
    }
  }

  void _jumpToChapter(int index) {
    setState(() => _currentIndex = index);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _loadChapter(index);
    // Pre-load neighbors
    if (index > 0) _loadChapter(index - 1);
    if (index < _chapters.length - 1) _loadChapter(index + 1);
  }

  void _handleTap(TapUpDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tapX = details.localPosition.dx;
    final third = screenWidth / 3;

    if (tapX < third) {
      _goToPreviousChapter();
    } else if (tapX > screenWidth - third) {
      _goToNextChapter();
    } else {
      setState(() => _showControls = !_showControls);
    }
  }

  void _scrollToTtsHighlight(int lineIndex) {
    if (!_scrollController.hasClients) return;
    final settings = ref.read(readerSettingsProvider);
    if (!settings.ttsAutoScroll) {
      _ttsScrollCeiling = null;
      return;
    }
    if (settings.scrollMode == 'paged') return;

    // Never scroll on the very first sentence — user is already positioned there.
    if (lineIndex == 0) {
      // Still update the ceiling so the user can't scroll past line 0's position.
      _updateTtsScrollCeiling(lineIndex);
      return;
    }

    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    final maxScroll = pos.maxScrollExtent;
    if (maxScroll <= 0) return;

    final viewportHeight = pos.viewportDimension;
    final currentScroll = pos.pixels;

    // ── Step 1: Character-offset ratio within the spoken chapter ────────────
    final ttsManager = ref.read(ttsManagerProvider.notifier);
    final charRatio = ttsManager.charOffsetRatioForLine(lineIndex).clamp(0.0, 1.0);

    // ── Step 2: Get ACTUAL rendered position of the chapter via GlobalKey ───
    final currentChapterId = (_chapters.isNotEmpty && _currentIndex < _chapters.length)
        ? _chapters[_currentIndex].id
        : -1;

    final chapterKey = _chapterContentKeys[currentChapterId];
    final renderBox = chapterKey?.currentContext?.findRenderObject() as RenderBox?;

    double chapterTop;
    double chapterHeight;

    if (renderBox != null && renderBox.hasSize) {
      final screenPos = renderBox.localToGlobal(Offset.zero);
      chapterTop = screenPos.dy + currentScroll;
      chapterHeight = renderBox.size.height;
    } else {
      return;
    }

    // ── Step 3: Compute estimated sentence pixel position within chapter ─────
    final sentencePixelOffset = chapterTop + (charRatio * chapterHeight);

    // Update the scroll ceiling to this sentence's position.
    // User can't scroll past here while TTS is active.
    _ttsScrollCeiling = sentencePixelOffset.clamp(0.0, maxScroll);

    // ── Step 4: Viewport comfort zone ────────────────────────────────────────
    final relativeToViewport = sentencePixelOffset - currentScroll;
    final zoneTop = viewportHeight * 0.10;
    final zoneBottom = viewportHeight * 0.65;

    if (relativeToViewport >= zoneTop && relativeToViewport <= zoneBottom) {
      return; // Sentence is comfortably in view — no scroll needed.
    }

    // ── Step 5: Scroll to place sentence at 25% down the viewport ────────────
    final rawTarget = sentencePixelOffset - viewportHeight * 0.25;
    final targetScroll = rawTarget
        .clamp(chapterTop, chapterTop + chapterHeight)
        .clamp(0.0, maxScroll);

    // TTS reads forward — never scroll backward.
    if (targetScroll <= currentScroll) return;

    // Skip micro-scrolls under 40px to avoid jitter.
    if (targetScroll - currentScroll < 40) return;

    _scrollController.animateTo(
      targetScroll,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  /// Computes the sentence pixel offset for [lineIndex] and updates
  /// [_ttsScrollCeiling] without triggering a scroll.
  void _updateTtsScrollCeiling(int lineIndex) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;

    final ttsManager = ref.read(ttsManagerProvider.notifier);
    final charRatio = ttsManager.charOffsetRatioForLine(lineIndex).clamp(0.0, 1.0);

    final currentChapterId = (_chapters.isNotEmpty && _currentIndex < _chapters.length)
        ? _chapters[_currentIndex].id
        : -1;
    final chapterKey = _chapterContentKeys[currentChapterId];
    final renderBox = chapterKey?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final screenPos = renderBox.localToGlobal(Offset.zero);
    final chapterTop = screenPos.dy + pos.pixels;
    final chapterHeight = renderBox.size.height;
    _ttsScrollCeiling = (chapterTop + charRatio * chapterHeight).clamp(0.0, pos.maxScrollExtent);
  }

  // ─── Bottom Sheets ────────────────────────────────────────

  void _showChapterList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Chapters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final ch = _chapters[index];
                  final isCurrent = index == _currentIndex;
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: isCurrent ? AppTheme.kPrimary.withValues(alpha: 0.2) : AppTheme.kSurfaceVariantDark,
                      child: Text('${index + 1}', style: TextStyle(fontSize: 12, color: isCurrent ? AppTheme.kPrimary : null)),
                    ),
                    title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                    onTap: () { Navigator.pop(context); _jumpToChapter(index); },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
        builder: (context, scrollController) => _ReaderSettingsSheet(scrollController: scrollController),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final ttsState = ref.watch(ttsManagerProvider);
    final ttsActive = ttsState.isSpeaking || ttsState.isPaused;

    // Auto-scroll when TTS highlight moves to a new line; clear ceiling when stopped.
    ref.listen(ttsManagerProvider, (prev, next) {
      if (next.isSpeaking && prev?.currentLineIndex != next.currentLineIndex) {
        _scrollToTtsHighlight(next.currentLineIndex);
      }
      // TTS stopped or paused — lift the scroll ceiling so user can scroll freely.
      if ((prev?.isSpeaking == true) && !next.isSpeaking) {
        _ttsScrollCeiling = null;
      }
    });

    // Increment version on every build to force HtmlWidget rebuild
    _settingsVersion++;

    return Scaffold(
      backgroundColor: settings.bgColor,
      body: GestureDetector(
        onTapUp: (details) {
          if (ttsActive) return; // Don't show controls when TTS is active
          _handleTap(details);
        },
        child: Stack(
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _buildError()
            else if (settings.scrollMode == 'paged')
              _buildPagedContent(settings)
            else
              _buildContinuousContent(settings),

            // Normal controls — hidden when TTS is active
            if (_showControls && !ttsActive) _buildTopBar(),
            if (_showControls && !ttsActive) _buildBottomBar(),
            if (_showControls && !ttsActive) _buildProgressBar(),

            // TTS floating player — shown when TTS is active
            if (ttsActive) _buildTtsFloatingPlayer(ttsState),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppTheme.kReaderTextDefault), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () { setState(() { _isLoading = true; _error = null; }); _loadChapters(); },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ─── Alignment helper ─────────────────────────────────────

  Map<String, String>? _alignmentStyles(ReaderSettings settings) {
    final alignment = settings.textAlignment;
    if (alignment == 'left' || alignment == 'center' || alignment == 'right' || alignment == 'justify') {
      return {'text-align': alignment};
    }
    return null;
  }

  Widget _buildChapterContent(_LoadedChapter loaded, ReaderSettings settings, TextStyle textStyle) {
    // PDF chapter
    if (loaded.html.startsWith('PDF:')) {
      final filePath = loaded.html.replaceFirst('PDF:', '');

      // pdfx doesn't support Linux — show a message
      if (Platform.isLinux) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.picture_as_pdf, size: 64, color: settings.textColor.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                'PDF viewing not supported on Linux',
                style: TextStyle(color: settings.textColor),
              ),
              const SizedBox(height: 8),
              Text(
                'File: ${filePath.split('/').last}',
                style: TextStyle(color: settings.textColor.withValues(alpha: 0.5), fontSize: 12),
              ),
            ],
          ),
        );
      }

      // On supported platforms, render with PdfView
      return SizedBox(
        height: 500,
        child: PdfView(
          controller: PdfController(
            document: PdfDocument.openFile(filePath),
          ),
        ),
      );
    }

    // HTML/EPUB chapter — apply TTS highlighting if active
    final ttsState = ref.watch(ttsManagerProvider);
    var html = loaded.html;
    if (ttsState.isSpeaking && ttsState.currentText.isNotEmpty) {
      html = TtsHighlighter.highlight(
        html, ttsState.currentText, ttsState.highlightMode,
        wordIndex: ttsState.currentWordIndex,
      );
    }

    // Include currentWordIndex in key so widget rebuilds on word change
    final highlightKey = ttsState.isSpeaking ? '-${ttsState.currentLineIndex}-${ttsState.currentWordIndex}' : '';

    return HtmlWidget(
      html,
      key: ValueKey('$_settingsVersion-${settings.textAlignment}-${settings.fontSize}-${settings.fontFamily}$highlightKey'),
      textStyle: textStyle,
      customStylesBuilder: (element) {
        final styles = _alignmentStyles(settings);
        if (element.localName == 'span') {
          final cls = element.attributes['class'] ?? '';
          if (cls.contains('tts-highlight-word')) {
            // Active word (child): bold filled background chip (pure inline TextSpan)
            return <String, String>{
              'background-color': 'rgba(61, 80, 250, 0.75)',
              'color': '#ffffff',
              'font-weight': 'bold',
            };
          } else if (cls.contains('tts-highlight')) {
            // Sentence context (parent): soft inline background tint (pure inline TextSpan)
            // NO border-radius/padding so flutter_widget_from_html keeps it inline
            // without creating full-width box containers or breaking text wrapping!
            return <String, String>{
              'background-color': 'rgba(61, 80, 250, 0.22)',
              'color': 'inherit',
            };
          }
        }
        return styles;
      },
    );
  }

  // Key to force HtmlWidget rebuild when settings change
  int _settingsVersion = 0;

  // ─── Continuous Mode ──────────────────────────────────────

  Widget _buildContinuousContent(ReaderSettings settings) {
    final textStyle = TextStyle(
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
      height: settings.lineHeight,
      color: settings.textColor,
    );

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: settings.paddingH, vertical: settings.paddingV),
      itemCount: _chapters.length,
      itemBuilder: (context, index) {
        // Show loading indicator for chapters not yet loaded
        final loaded = _chapterCache[_chapters[index].id];
        if (loaded == null) {
          if (index > _currentIndex) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return const SizedBox.shrink();
        }

        // Chapter divider — only for online chapters, not EPUBs
        final isEpub = loaded.chapter.url.startsWith('epub://');
        if (index > 0 && !isEpub) {
          return Column(
            children: [
              const SizedBox(height: 64),
              // Chapter divider — full-width with chapter title
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    // Top line
                    Container(
                      height: 1,
                      color: settings.textColor.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 24),
                    // Chapter number
                    Text(
                      'Chapter ${index + 1}',
                      style: TextStyle(
                        color: settings.textColor.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Chapter title
                    Text(
                      loaded.chapter.name,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: settings.textColor,
                        fontSize: settings.fontSize + 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Bottom line
                    Container(
                      height: 1,
                      color: settings.textColor.withValues(alpha: 0.2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              // Chapter content — HTML or PDF
              KeyedSubtree(
                key: _chapterContentKeys.putIfAbsent(_chapters[index].id, () => GlobalKey()),
                child: _buildChapterContent(loaded, settings, textStyle),
              ),
            ],
          );
        }

        // First chapter — no divider
        return KeyedSubtree(
          key: _chapterContentKeys.putIfAbsent(_chapters[index].id, () => GlobalKey()),
          child: _buildChapterContent(loaded, settings, textStyle),
        );
      },
    );
  }

  // ─── Paged Mode ───────────────────────────────────────────

  Widget _buildPagedContent(ReaderSettings settings) {
    final textStyle = TextStyle(
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
      height: settings.lineHeight,
      color: settings.textColor,
    );

    return Column(
      children: [
        // Page content
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _chapters.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
              _loadChapter(index);
              if (index > 0) _loadChapter(index - 1);
              if (index < _chapters.length - 1) _loadChapter(index + 1);
            },
            itemBuilder: (context, index) {
              final loaded = _chapterCache[_chapters[index].id];
              if (loaded == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: settings.paddingH, vertical: settings.paddingV),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Chapter title at top
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        loaded.chapter.name,
                        style: TextStyle(
                          color: settings.textColor,
                          fontSize: settings.fontSize + 4,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _buildChapterContent(loaded, settings, textStyle),
                  ],
                ),
              );
            },
          ),
        ),

        // Page navigation bar
        Container(
          color: settings.bgColor,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Previous page
              TextButton.icon(
                onPressed: _currentIndex > 0 ? _goToPreviousChapter : null,
                icon: const Icon(Icons.chevron_left, size: 20),
                label: const Text('Previous'),
              ),

              // Chapter indicator
              Text(
                '${_currentIndex + 1} / ${_chapters.length}',
                style: TextStyle(color: settings.textColor.withValues(alpha: 0.7), fontSize: 13),
              ),

              // Next page
              TextButton.icon(
                onPressed: _currentIndex < _chapters.length - 1 ? _goToNextChapter : null,
                icon: const Text('Next'),
                label: const Icon(Icons.chevron_right, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Controls Overlay ─────────────────────────────────────

  Widget _buildTopBar() {
    final settings = ref.watch(readerSettingsProvider);
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent]),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () { SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); Navigator.pop(context); },
                ),
                Expanded(
                  child: Text(
                    _chapters.isNotEmpty ? _chapters[_currentIndex].name : 'Chapter',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.bookmark_border, color: Colors.white),
                  onPressed: _addBookmark,
                ),
                IconButton(
                  icon: const Icon(Icons.bookmarks, color: Colors.white),
                  onPressed: _showBookmarks,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black54, Colors.transparent]),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white), onPressed: _goToPreviousChapter),
                IconButton(
                  icon: const Icon(Icons.record_voice_over, color: Colors.white),
                  onPressed: () => _toggleTts(),
                ),
                IconButton(icon: const Icon(Icons.list, color: Colors.white), onPressed: _showChapterList),
                IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: _showSettingsDialog),
                IconButton(icon: const Icon(Icons.skip_next, color: Colors.white), onPressed: _goToNextChapter),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// TTS controls — same style as the normal bottom bar.
  Widget _buildTtsFloatingPlayer(TtsManagerState ttsState) {
    final progress = ttsState.totalLines > 0
        ? ttsState.currentLineIndex / ttsState.totalLines
        : 0.0;

    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black54, Colors.transparent]),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Controls row — same layout as normal bottom bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                      onPressed: () => ref.read(ttsManagerProvider.notifier).skipBackward(),
                    ),
                    IconButton(
                      icon: Icon(
                        ttsState.isPaused ? Icons.play_arrow : Icons.pause,
                        color: ttsState.isPaused ? Colors.white : AppTheme.kPrimary,
                      ),
                      onPressed: () => ref.read(ttsManagerProvider.notifier).togglePause(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop, color: Colors.white),
                      onPressed: () => ref.read(ttsManagerProvider.notifier).stop(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                      onPressed: () => ref.read(ttsManagerProvider.notifier).skipForward(),
                    ),
                  ],
                ),
              ),
              // Thin progress bar
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.kPrimary),
                minHeight: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleTts() async {
    final ttsState = ref.read(ttsManagerProvider);
    final ttsNotifier = ref.read(ttsManagerProvider.notifier);

    if (ttsState.isSpeaking || ttsState.isPaused) {
      ttsNotifier.stop();
      return;
    }

    // Start TTS for current chapter
    if (_chapters.isEmpty || _currentIndex >= _chapters.length) return;
    final chapter = _chapters[_currentIndex];
    final loaded = _chapterCache[chapter.id];
    if (loaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chapter not loaded yet')),
      );
      return;
    }

    // Get novel info for media controls (title + cover + author)
    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(widget.novelId);
    ttsNotifier.startFromHtml(
      loaded.html,
      coverUrl: novel?.coverUrl,
      novelTitle: novel?.title,
      novelAuthor: novel?.author,
    );
  }

  Widget _buildProgressBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: LinearProgressIndicator(
        value: _scrollProgress,
        backgroundColor: Colors.white24,
        valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.kPrimary),
        minHeight: 2,
      ),
    );
  }
}

// ─── Settings Sheet (same as before) ────────────────────────

class _ReaderSettingsSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  const _ReaderSettingsSheet({required this.scrollController});

  @override
  ConsumerState<_ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends ConsumerState<_ReaderSettingsSheet> {
  List<String> _systemFonts = [];
  bool _loadingFonts = true;

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    final fonts = await getSystemFonts();
    setState(() { _systemFonts = fonts; _loadingFonts = false; });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Reader Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              _buildSection('Font'),
              ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                title: const Text('Font Family'),
                subtitle: Text(settings.fontFamily.isEmpty ? 'System Default' : settings.fontFamily,
                    style: TextStyle(fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showFontPicker(settings, notifier),
              ),
              const SizedBox(height: 12),
              _buildSlider('Size', settings.fontSize, 10, 30, '${settings.fontSize.round()} sp', (v) => notifier.updateFontSize(v)),
              _buildSlider('Line Height', settings.lineHeight, 1.0, 3.0, settings.lineHeight.toStringAsFixed(1), (v) => notifier.updateLineHeight(v)),

              const SizedBox(height: 16),
              _buildSection('Layout'),
              _buildSlider('H Padding', settings.paddingH, 0, 50, '${settings.paddingH.round()}', (v) => notifier.updatePaddingH(v)),
              _buildSlider('V Padding', settings.paddingV, 0, 50, '${settings.paddingV.round()}', (v) => notifier.updatePaddingV(v)),
              _buildSlider('Paragraph Gap', settings.paragraphSpacing, 0, 40, '${settings.paragraphSpacing.round()}', (v) => notifier.updateParagraphSpacing(v)),

              const SizedBox(height: 16),
              _buildSection('Text'),
              _buildAlignmentRow(settings, notifier),

              const SizedBox(height: 16),
              _buildSection('Display'),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('TTS Auto-Scroll'), subtitle: const Text('Auto-scroll reader while TTS is reading'), value: settings.ttsAutoScroll, onChanged: (_) => notifier.toggleTtsAutoScroll()),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Bionic Reading'), subtitle: const Text('Bold first half of each word'), value: settings.bionicReading, onChanged: (_) => notifier.toggleBionicReading()),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Selectable Text'), value: settings.selectableText, onChanged: (_) => notifier.toggleSelectableText()),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Show Time'), value: settings.showTime, onChanged: (_) => notifier.toggleShowTime()),
              if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) ...[
                SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Show Battery'), value: settings.showBattery, onChanged: (_) => notifier.toggleShowBattery()),
                SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Keep Screen On'), value: settings.keepScreenOn, onChanged: (_) => notifier.toggleKeepScreenOn()),
              ],

              const SizedBox(height: 16),
              _buildSection('Scroll'),
              _buildRadioTile('Continuous', 'continuous', settings.scrollMode, (v) => notifier.updateScrollMode(v!)),
              _buildRadioTile('Paged', 'paged', settings.scrollMode, (v) => notifier.updateScrollMode(v!)),

              if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) ...[
                const SizedBox(height: 16),
                _buildSection('Orientation'),
                _buildRadioTile('Auto', 'auto', settings.orientation, (v) => notifier.updateOrientation(v!)),
                _buildRadioTile('Portrait', 'portrait', settings.orientation, (v) => notifier.updateOrientation(v!)),
                _buildRadioTile('Landscape', 'landscape', settings.orientation, (v) => notifier.updateOrientation(v!)),
              ],

              const SizedBox(height: 16),
              _buildSection('Theme'),
              _buildThemeRow(settings, notifier),
            ],
          ),
        ),
      ],
    );
  }

  void _showFontPicker(ReaderSettings settings, ReaderSettingsNotifier notifier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5, maxChildSize: 0.8, minChildSize: 0.3, expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Select Font', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _systemFonts.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ListTile(
                      leading: Icon(settings.fontFamily.isEmpty ? Icons.check_circle : Icons.circle_outlined, color: settings.fontFamily.isEmpty ? AppTheme.kPrimary : null),
                      title: const Text('System Default'),
                      onTap: () { notifier.updateFontFamily(''); Navigator.pop(context); },
                    );
                  }
                  final font = _systemFonts[index - 1];
                  final isSelected = settings.fontFamily.toLowerCase() == font.toLowerCase();
                  return ListTile(
                    leading: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? AppTheme.kPrimary : null),
                    title: Text(font, style: TextStyle(fontFamily: font, fontSize: 16)),
                    onTap: () { notifier.updateFontFamily(font); Navigator.pop(context); },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.kTextSecondaryDark)));
  }

  Widget _buildSlider(String label, double value, double min, double max, String display, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
        SizedBox(width: 40, child: Text(display, style: const TextStyle(fontSize: 12))),
      ]),
    );
  }

  Widget _buildAlignmentRow(ReaderSettings settings, ReaderSettingsNotifier notifier) {
    return Row(children: [
      const SizedBox(width: 80, child: Text('Align', style: TextStyle(fontSize: 13))),
      Expanded(child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'left', icon: Icon(Icons.format_align_left, size: 18)),
          ButtonSegment(value: 'center', icon: Icon(Icons.format_align_center, size: 18)),
          ButtonSegment(value: 'right', icon: Icon(Icons.format_align_right, size: 18)),
          ButtonSegment(value: 'justify', icon: Icon(Icons.format_align_justify, size: 18)),
        ],
        selected: {settings.textAlignment},
        onSelectionChanged: (s) => notifier.updateTextAlignment(s.first),
      )),
    ]);
  }

  Widget _buildRadioTile(String title, String value, String groupValue, ValueChanged<String?> onChanged) {
    return RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, title: Text(title), value: value, groupValue: groupValue, onChanged: onChanged);
  }

  Widget _buildThemeRow(ReaderSettings settings, ReaderSettingsNotifier notifier) {
    return Wrap(spacing: 12, runSpacing: 8, children: [
      _themeCircle('Dark', 'dark', AppTheme.kReaderBgDefault, AppTheme.kReaderTextDefault, settings, notifier),
      _themeCircle('Light', 'light', AppTheme.kReaderBgColors['light']!, AppTheme.kReaderTextColors['light']!, settings, notifier),
      _themeCircle('Sepia', 'sepia', AppTheme.kReaderBgColors['sepia']!, AppTheme.kReaderTextColors['sepia']!, settings, notifier),
      _themeCircle('Green', 'green', AppTheme.kReaderBgColors['green']!, AppTheme.kReaderTextColors['green']!, settings, notifier),
      _themeCircle('Blue', 'blue', AppTheme.kReaderBgColors['blue']!, AppTheme.kReaderTextColors['blue']!, settings, notifier),
    ]);
  }

  Widget _themeCircle(String label, String themeKey, Color bg, Color text, ReaderSettings settings, ReaderSettingsNotifier notifier) {
    final isSelected = settings.readerTheme == themeKey;
    return GestureDetector(
      onTap: () => notifier.updateReaderTheme(themeKey),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle, border: Border.all(
            color: isSelected ? AppTheme.kPrimary : Colors.grey.withValues(alpha: 0.3), width: isSelected ? 3 : 1)),
          child: Center(child: Text('Aa', style: TextStyle(color: text, fontSize: 12, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, color: isSelected ? AppTheme.kPrimary : null, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      ]),
    );
  }
}
