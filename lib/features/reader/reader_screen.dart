import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:epubx/epubx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../core/providers/engine.dart';
import '../../core/providers/registry.dart';
import '../../core/network/client.dart';
import '../../core/utils/html_preprocessor.dart';
import '../../core/utils/logger.dart';
import '../../theme/app_theme.dart';
import '../../core/tts/tts_manager.dart';
import '../settings/pages/reader_settings_page.dart';
import '../../core/translation/translation_service.dart';
import '../settings/pages/translation_settings_page.dart';
import 'widgets/reader_settings_sheet.dart';

import 'widgets/bookmark_sheet.dart';
import 'widgets/chapter_sheet.dart';
import 'widgets/reader_controls.dart';
import 'widgets/reader_content_view.dart';
import 'widgets/translate_dialog.dart' as translate;

const _tag = 'Reader';

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
  final Map<int, LoadedChapter> _chapterCache = {};
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  double _scrollProgress = 0.0;

  // EPUB Table of Contents (parsed from NCX/OPF)
  List<EpubNavigationPoint> _epubToc = [];

  // GlobalKeys for each HTML paragraph chunk widget, so we can use
  // Scrollable.ensureVisible to scroll directly to the active chunk.
  final Map<String, GlobalKey> _chunkKeys = {};

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

    // Auto-load next chapters when near bottom (continuous mode)
    final settings = ref.read(readerSettingsProvider);
    if (settings.scrollMode == 'continuous' && progress > 0.85) {
      final firstVisible = (pos.pixels / MediaQuery.of(context).size.height).floor();
      final start = _currentIndex + 1;
      final end = (firstVisible + 5).clamp(start, _chapters.length);
      for (var i = start; i < end; i++) {
        _loadChapter(i);
      }
    }

    // TTS scroll ceiling: when auto-scroll is on and TTS is active,
    // prevent the user from scrolling forward past the current sentence.
    final ceiling = _ttsScrollCeiling;
    if (ceiling != null && settings.ttsAutoScroll) {
      final ttsState = ref.read(ttsManagerProvider);
      if (ttsState.isSpeaking && pos.pixels > ceiling + 1) {
        _scrollController.jumpTo(ceiling);
      }
    }
  }

  // ─── Chapter Loading ──────────────────────────────────────

  Future<void> _loadChapters() async {
    try {
      final chapterDao = ref.read(chapterDaoProvider);
      _chapters = await chapterDao.getChaptersForNovel(widget.novelId);
      _currentIndex = _chapters.indexWhere((c) => c.id == widget.chapterId);
      if (_currentIndex < 0) _currentIndex = 0;

      Log.i(_tag, 'Loaded ${_chapters.length} chapters, starting at index $_currentIndex');

      _saveHistory();

      final isEpub = _chapters.isNotEmpty && _chapters.first.url.startsWith('epub://');

      if (isEpub) {
        for (var i = 0; i < _chapters.length; i++) {
          await _loadChapter(i);
        }
      } else {
        await _loadChapter(_currentIndex);
        final settings = ref.read(readerSettingsProvider);
        if (settings.scrollMode == 'continuous') {
          for (var i = 1; i <= 3 && _currentIndex + i < _chapters.length; i++) {
            _loadChapter(_currentIndex + i);
          }
        } else if (_currentIndex < _chapters.length - 1) {
          _loadChapter(_currentIndex + 1);
        }
      }
    } catch (e) {
      Log.e(_tag, 'Failed to load chapters', e);
      _error = 'Failed to load chapters. Check your connection and try again.';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    _restoreReadingPosition();
  }

  void _restoreReadingPosition() async {
    final historyDao = ref.read(historyDaoProvider);
    final latest = await historyDao.getLatestHistoryForNovel(widget.novelId);
    if (latest == null || latest.scrollPosition == null) return;
    if (latest.chapterId != widget.chapterId) return;

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

    double position = 0.0;
    if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
      position = _scrollController.position.pixels / _scrollController.position.maxScrollExtent;
    }

    if (!context.mounted) return;
    final note = await showAddBookmarkDialog(context, chapterName: chapter.name);

    final bookmarkDao = ref.read(bookmarkDaoProvider);
    await bookmarkDao.addBookmark(BookmarksCompanion(
      novelId: Value(widget.novelId),
      chapterId: Value(chapter.id),
      position: Value(position.toStringAsFixed(4)),
      note: note != null && note.isNotEmpty ? Value(note) : const Value.absent(),
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

    showBookmarkSheet(
      context: context,
      bookmarks: bookmarks,
      chapters: _chapters,
      onTapBookmark: (chapterIndex, pos) {
        _jumpToChapter(chapterIndex);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && _scrollController.position.hasContentDimensions) {
            _scrollController.jumpTo(pos * _scrollController.position.maxScrollExtent);
          }
        });
      },
      onDeleteBookmark: (bookmarkId) async {
        await bookmarkDao.removeBookmark(bookmarkId);
        if (mounted) _showBookmarks();
      },
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
      if (_currentIndex == index && _chapterCache[_chapters[index].id] == null) {
        _error = 'Failed to load chapter "${chapter.name}". Check your connection and try again.';
        if (mounted) setState(() {});
      }
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

    if (_epubToc.isEmpty && book.Schema?.Navigation?.NavMap?.Points != null) {
      _epubToc = book.Schema!.Navigation!.NavMap!.Points!;
      Log.ok(_tag, 'EPUB TOC: ${_epubToc.length} top-level entries');
    }

    final chIndex = index.clamp(0, book.Chapters!.length - 1);
    final ch = book.Chapters![chIndex];
    final html = ch.HtmlContent ?? '';
    final cleanHtml = HtmlPreprocessor.clean(html, keepCss: true);
    _chapterCache[chapter.id] = LoadedChapter(chapter: chapter, html: cleanHtml);
    Log.ok(_tag, 'EPUB chapter ${chIndex + 1} loaded: ${cleanHtml.length} chars');
    setState(() {});
  }

  Future<void> _loadPdfChapter(Chapter chapter, int index) async {
    final url = chapter.url;
    final filePath = url.replaceFirst('pdf://', '').split('#').first;

    Log.i(_tag, 'Loading PDF page from: $filePath');

    final file = File(filePath);
    if (!await file.exists()) {
      Log.e(_tag, 'PDF file not found: $filePath');
      return;
    }

    _chapterCache[chapter.id] = LoadedChapter(
      chapter: chapter,
      html: 'PDF:$filePath',
    );
    Log.ok(_tag, 'PDF chapter ${index + 1} marked for PDF rendering');
    setState(() {});
  }

  Future<void> _loadRemoteChapter(Chapter chapter, int index) async {
    try {
      final dio = await ref.read(dioProvider.future);

      final novelDao = ref.read(novelDaoProvider);
      final novel = await novelDao.getNovelById(widget.novelId);
      if (novel == null) {
        Log.w(_tag, 'Novel not found for id ${widget.novelId}');
        if (_currentIndex == index) {
          _error = 'Novel data not found. Try re-adding the novel.';
          if (mounted) setState(() {});
        }
        return;
      }

      // Use cached provider instance
      final instance = await loadProviderById(novel.providerId, ref);
      if (instance == null) {
        Log.w(_tag, 'No provider cached for ${novel.providerId}');
        if (_currentIndex == index) {
          _error = 'Provider not available. Please sync providers in settings.';
          if (mounted) setState(() {});
        }
        return;
      }
      final contentUrl = await instance.getChapterContentUrl(chapter.url);
      if (contentUrl == null) {
        Log.w(_tag, 'No content URL for chapter');
        if (_currentIndex == index) {
          _error = 'Could not determine chapter URL.';
          if (mounted) setState(() {});
        }
        return;
      }

      final response = await dio.get(contentUrl);
      final html = response.data.toString();
      final content = await instance.parseChapterContent(html);

      if (content != null && content.html.isNotEmpty) {
        final cleanHtml = HtmlPreprocessor.clean(content.html);
        _chapterCache[chapter.id] = LoadedChapter(chapter: chapter, html: cleanHtml);
        Log.ok(_tag, 'Chapter loaded: ${cleanHtml.length} chars');
        setState(() {});
        return;
      }
      Log.w(_tag, 'Empty content for chapter ${index + 1}');
      if (_currentIndex == index) {
        _error = 'Failed to load chapter "${chapter.name}" — no content returned.';
        if (mounted) setState(() {});
      }
    } catch (e) {
      Log.e(_tag, 'Failed to load chapter', e);
      if (_currentIndex == index && _chapterCache[_chapters[index].id] == null) {
        _error = 'Failed to load chapter "${chapter.name}". Check your connection and try again.';
        if (mounted) setState(() {});
      }
    }
  }

  void _preloadSurrounding() {
    for (var i = 1; i <= 3; i++) {
      if (_currentIndex - i >= 0) _loadChapter(_currentIndex - i);
      if (_currentIndex + i < _chapters.length) _loadChapter(_currentIndex + i);
    }
  }

  // ─── Navigation ───────────────────────────────────────────

  void _goToPreviousChapter() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _loadChapter(_currentIndex);
      _preloadSurrounding();
    }
  }

  void _goToNextChapter() {
    if (_currentIndex < _chapters.length - 1) {
      setState(() => _currentIndex++);
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _loadChapter(_currentIndex);
      _preloadSurrounding();
    }
  }

  void _jumpToChapter(int index) {
    setState(() => _currentIndex = index);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _loadChapter(index);
    _preloadSurrounding();
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
    if (!settings.ttsAutoScroll) return;
    if (settings.scrollMode == 'paged') return;

    final ttsState = ref.read(ttsManagerProvider);
    final currentChapterId = (_chapters.isNotEmpty && _currentIndex < _chapters.length)
        ? _chapters[_currentIndex].id
        : -1;

    final chunkKey = _chunkKeys['$currentChapterId-${ttsState.currentChunkIndex}'];
    if (chunkKey?.currentContext != null) {
      Scrollable.ensureVisible(
        chunkKey!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        alignment: 0.25,
      );
    }
  }

  // ─── Bottom Sheets ────────────────────────────────────────

  void _showChapterList() {
    showChapterListSheet(
      context: context,
      chapters: _chapters,
      currentIndex: _currentIndex,
      onJumpToChapter: _jumpToChapter,
    );
  }

  void _showEpubToc() {
    if (_epubToc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No table of contents available')),
      );
      return;
    }

    showEpubTocSheet(
      context: context,
      epubToc: _epubToc,
      chapters: _chapters,
      onJumpToChapter: _jumpToChapter,
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
        builder: (context, scrollController) => ReaderSettingsSheet(scrollController: scrollController),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────

  // Key to force HtmlWidget rebuild when settings change
  int _settingsVersion = 0;

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
      if ((prev?.isSpeaking == true) && !next.isSpeaking) {
        _ttsScrollCeiling = null;
        final settings = ref.read(readerSettingsProvider);
        if (settings.ttsAutoAdvance && _currentIndex < _chapters.length - 1) {
          _autoAdvanceTts();
        }
      }
    });

    _settingsVersion++;

    return Scaffold(
      backgroundColor: settings.bgColor,
      body: GestureDetector(
        onTapUp: (details) {
          if (ttsActive) return;
          _handleTap(details);
        },
        child: Stack(
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _buildError()
            else if (settings.scrollMode == 'paged')
              buildPagedContent(
                context: context,
                settings: settings,
                chapters: _chapters,
                currentIndex: _currentIndex,
                chapterCache: _chapterCache,
                pageController: _pageController,
                onPageChanged: (index) => setState(() => _currentIndex = index),
                loadChapter: _loadChapter,
                goToPreviousChapter: _goToPreviousChapter,
                goToNextChapter: _goToNextChapter,
                chunkKeys: _chunkKeys,
                settingsVersion: _settingsVersion,
                ttsState: ttsState,
              )
            else
              buildContinuousContent(
                context: context,
                settings: settings,
                chapters: _chapters,
                currentIndex: _currentIndex,
                chapterCache: _chapterCache,
                scrollController: _scrollController,
                loadChapter: _loadChapter,
                chunkKeys: _chunkKeys,
                settingsVersion: _settingsVersion,
                ttsState: ttsState,
              ),

            // Normal controls — hidden when TTS is active
            if (_showControls && !ttsActive)
              buildReaderTopBar(
                context: context,
                chapterName: _chapters.isNotEmpty ? _chapters[_currentIndex].name : 'Chapter',
                onBack: () => Navigator.pop(context),
                onAddBookmark: _addBookmark,
                onShowBookmarks: _showBookmarks,
              ),
            if (_showControls && !ttsActive)
              buildReaderBottomBar(
                onPrevious: _goToPreviousChapter,
                onNext: _goToNextChapter,
                onToggleTts: () => _toggleTts(),
                onShowChapterList: _showChapterList,
                hasEpubToc: _epubToc.isNotEmpty,
                onShowEpubToc: _showEpubToc,
                onTranslate: _translateChapter,
                onSettings: _showSettingsDialog,
              ),
            if (_showControls && !ttsActive) buildReaderProgressBar(_scrollProgress),

            // TTS floating player — shown when TTS is active
            if (ttsActive)
              buildTtsFloatingPlayer(
                ttsState: ttsState,
                onSkipBack: () => ref.read(ttsManagerProvider.notifier).skipBackward(),
                onTogglePause: () => ref.read(ttsManagerProvider.notifier).togglePause(),
                onStop: () => ref.read(ttsManagerProvider.notifier).stop(),
                onSkipNext: () => ref.read(ttsManagerProvider.notifier).skipForward(),
                onShowTranslateDialog: () => translate.showTranslateDialog(context, ref),
              ),
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

  // ─── TTS ──────────────────────────────────────────────────

  void _toggleTts() async {
    final ttsState = ref.read(ttsManagerProvider);
    final ttsNotifier = ref.read(ttsManagerProvider.notifier);

    if (ttsState.isSpeaking || ttsState.isPaused) {
      ttsNotifier.stop();
      return;
    }

    if (_chapters.isEmpty || _currentIndex >= _chapters.length) return;
    final chapter = _chapters[_currentIndex];
    final loaded = _chapterCache[chapter.id];
    if (loaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chapter not loaded yet')),
      );
      return;
    }

    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(widget.novelId);
    ttsNotifier.startFromHtml(
      loaded.html,
      coverUrl: novel?.coverUrl,
      novelTitle: novel?.title,
      novelAuthor: novel?.author,
    );
  }

  void _autoAdvanceTts() async {
    if (_currentIndex >= _chapters.length - 1) return;

    final nextIndex = _currentIndex + 1;
    setState(() => _currentIndex = nextIndex);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await _loadChapter(nextIndex);
    _preloadSurrounding();

    final chapter = _chapters[nextIndex];
    final loaded = _chapterCache[chapter.id];
    if (loaded == null) return;

    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(widget.novelId);
    final ttsNotifier = ref.read(ttsManagerProvider.notifier);
    ttsNotifier.startFromHtml(
      loaded.html,
      coverUrl: novel?.coverUrl,
      novelTitle: novel?.title,
      novelAuthor: novel?.author,
    );
  }

  // ─── Translation ──────────────────────────────────────────

  void _translateChapter() async {
    if (_chapters.isEmpty || _currentIndex >= _chapters.length) return;
    final chapter = _chapters[_currentIndex];
    final loaded = _chapterCache[chapter.id];
    if (loaded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chapter not loaded yet')),
      );
      return;
    }

    final translationSettings = ref.read(translationSettingsProvider);
    final sourceLang = translationSettings.fromLanguage;
    final targetLang = translationSettings.toLanguage;

    if (sourceLang == targetLang) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Source and target language are the same')),
      );
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Translating...'), duration: Duration(seconds: 3)),
    );

    try {
      final service = ref.read(translationServiceProvider);

      final paragraphRegex = RegExp(r'<(p|div|h[1-6]|li|blockquote)[^>]*>(.*?)</\1>', dotAll: true);
      final matches = paragraphRegex.allMatches(loaded.html).toList();

      if (matches.isEmpty) {
        final plainText = loaded.html.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        final translated = await service.translate(plainText, sourceLang: sourceLang, targetLang: targetLang);
        _chapterCache[chapter.id] = LoadedChapter(chapter: chapter, html: '<p>$translated</p>');
      } else {
        final buffer = StringBuffer();
        for (final match in matches) {
          final tag = match.group(1)!;
          final innerHtml = match.group(2)!;
          final plainText = innerHtml.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

          if (plainText.isEmpty) {
            buffer.write(match.group(0));
            continue;
          }

          final translated = await service.translate(plainText, sourceLang: sourceLang, targetLang: targetLang);
          buffer.write('<$tag>$translated</$tag>\n');
        }
        _chapterCache[chapter.id] = LoadedChapter(chapter: chapter, html: buffer.toString());
      }

      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Translation complete')),
        );
      }
    } catch (e) {
      Log.e(_tag, 'Translation failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Translation failed: $e')),
        );
      }
    }
  }
}

