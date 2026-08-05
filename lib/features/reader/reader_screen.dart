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
import '../settings/pages/reader/reader_settings_state.dart';
import 'widgets/bookmark_sheet.dart';
import 'widgets/chapter_sheet.dart';
import 'widgets/reader_content_view.dart';
import 'widgets/reader_controls.dart';
import 'widgets/reader_settings_sheet.dart';
import 'widgets/translate_dialog.dart' as translate;

class ReaderScreen extends ConsumerStatefulWidget {
  final int novelId;
  final int chapterId;
  const ReaderScreen({super.key, required this.novelId, required this.chapterId});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _showControls = false;
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  double _scrollProgress = 0.0;
  final Map<String, GlobalKey> _chunkKeys = {};
  double? _ttsScrollCeiling;
  int _settingsVersion = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _scrollController.addListener(_onScroll);

    ref.read(readerNavigationProvider(widget.novelId).notifier)
        .loadChapters(widget.chapterId);
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
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    final chapter = nav.currentChapter;
    if (chapter == null || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final progress = pos.hasContentDimensions && pos.maxScrollExtent > 0
        ? pos.pixels / pos.maxScrollExtent
        : 0.0;
    ref.read(readerNavigationProvider(widget.novelId).notifier)
        .saveReadingPosition(progress);
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

  void _goToPreviousChapter() {
    ref.read(readerNavigationProvider(widget.novelId).notifier).goToPreviousChapter();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _restoreReadingPosition();
  }

  void _goToNextChapter() {
    ref.read(readerNavigationProvider(widget.novelId).notifier).goToNextChapter();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _jumpToChapter(int index) {
    ref.read(readerNavigationProvider(widget.novelId).notifier).jumpToChapter(index);
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _restoreReadingPosition();
  }

  void _restoreReadingPosition() async {
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    final chapter = nav.currentChapter;
    if (chapter == null) return;
    final pos = await ref.read(readerNavigationProvider(widget.novelId).notifier)
        .restoreReadingPosition(chapter.id);
    if (pos != null && pos > 0 && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll > 0) _scrollController.jumpTo(pos * maxScroll);
      });
    }
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
    final chunkKey = _chunkKeys['${chapter.id}-${ttsState.currentChunkIndex}'];
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

    final chapterContent = ref.read(contentProvider.notifier).getChapter(chapter.id);
    if (chapterContent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chapter not loaded yet')),
      );
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
    final paragraphs = doc.blocks
        .whereType<ParagraphNode>()
        .map((p) => p.children.whereType<TextNode>().map((t) => t.text).join())
        .where((t) => t.trim().isNotEmpty)
        .toList();

    if (paragraphs.isEmpty) return;

    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(widget.novelId);
    ref.read(ttsManagerProvider.notifier).startFromParagraphs(
      paragraphs,
      coverUrl: novel?.coverUrl,
      novelTitle: novel?.title,
      novelAuthor: novel?.author,
    );
  }

  void _autoAdvanceTts() async {
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    if (nav.currentIndex >= nav.chapters.length - 1) return;

    final currentChapter = nav.currentChapter;
    if (currentChapter != null) {
      // Mark current chapter as TTS-read
      await ref.read(chapterDaoProvider).markChapterAsTtsRead(currentChapter.id);
    }

    _goToNextChapter();
    final nextChapter = ref.read(readerNavigationProvider(widget.novelId)).currentChapter;
    if (nextChapter == null) return;

    // Wait for chapter content to load
    await ref.read(contentProvider.notifier).loadChapter(nextChapter.id);
    final chapterContent = ref.read(contentProvider.notifier).getChapter(nextChapter.id);
    if (chapterContent == null || chapterContent.isPdf) return;

    final doc = MDParser.parse(chapterContent.data);
    final paragraphs = doc.blocks
        .whereType<ParagraphNode>()
        .map((p) => p.children.whereType<TextNode>().map((t) => t.text).join())
        .where((t) => t.trim().isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return;

    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(widget.novelId);
    ref.read(ttsManagerProvider.notifier).startFromParagraphs(
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
    final note = await showAddBookmarkDialog(context, chapterName: chapter.name);
    if (note == null) return;

    final bookmarkDao = ref.read(bookmarkDaoProvider);
    await bookmarkDao.addBookmark(BookmarksCompanion(
      novelId: Value(widget.novelId),
      chapterId: Value(chapter.id),
      position: Value(_scrollProgress.toStringAsFixed(4)),
      note: note.isNotEmpty ? Value(note) : const Value.absent(),
      createdAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bookmarked: ${chapter.name}'), duration: const Duration(seconds: 1)),
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

  void _showChapterList() {
    final nav = ref.read(readerNavigationProvider(widget.novelId));
    showChapterListSheet(
      context: context,
      chapters: nav.chapters,
      currentIndex: nav.currentIndex,
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

  Map<int, ChapterContent> _buildContentMap(ContentState state) {
    return Map.fromEntries(
      state.chapters.entries
          .where((e) => e.value is AsyncData<ChapterContent>)
          .map((e) => MapEntry(e.key, (e.value as AsyncData<ChapterContent>).value)),
    );
  }

  Map<int, String> _buildErrorMap(ContentState state) {
    return Map.fromEntries(
      state.chapters.entries
          .where((e) => e.value is AsyncError<ChapterContent>)
          .map((e) => MapEntry(e.key, (e.value as AsyncError<ChapterContent>).error.toString())),
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

    // Restore reading position when available
    ref.listen<double?>(
      readerNavigationProvider(widget.novelId).select((s) => s.restoredScrollPosition),
      (prev, pos) {
        if (pos != null && pos > 0 && _scrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scrollController.hasClients) return;
            final maxScroll = _scrollController.position.maxScrollExtent;
            if (maxScroll > 0) {
              _scrollController.jumpTo(pos * maxScroll);
            }
          });
          ref.read(readerNavigationProvider(widget.novelId).notifier).clearRestoredScrollPosition();
        }
      },
    );

    _settingsVersion++;

    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

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
                      ref.read(readerNavigationProvider(widget.novelId).notifier).jumpToChapter(index);
                    },
                    loadChapter: (chapterId) => ref.read(contentProvider.notifier).loadChapter(chapterId),
                    goToPreviousChapter: _goToPreviousChapter,
                    goToNextChapter: _goToNextChapter,
                    chunkKeys: _chunkKeys,
                    settingsVersion: _settingsVersion,
                    ttsState: ttsState,
                  )
                : buildContinuousContent(
                    context: context,
                    settings: settings,
                    chapters: nav.chapters,
                    currentIndex: nav.currentIndex,
                    contentCache: contentCache,
                    errorCache: errorCache,
                    scrollController: _scrollController,
                    loadChapter: (chapterId) => ref.read(contentProvider.notifier).loadChapter(chapterId),
                    chunkKeys: _chunkKeys,
                    settingsVersion: _settingsVersion,
                    ttsState: ttsState,
                  );

    return Scaffold(
      backgroundColor: settings.bgColor,
      body: isDesktop
          ? CallbackShortcuts(
              bindings: {
                SingleActivator(LogicalKeyboardKey.arrowLeft): _goToPreviousChapter,
                SingleActivator(LogicalKeyboardKey.arrowRight): _goToNextChapter,
                SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
                SingleActivator(LogicalKeyboardKey.space): () {
                  setState(() => _showControls = !_showControls);
                },
              },
              child: Focus(
                autofocus: true,
                child: GestureDetector(
                  onTapUp: (details) {
                    if (ttsActive) return;
                    _handleTap(details);
                  },
                  child: Stack(
                    children: [
                      readerBody,
                      ..._overlayWidgets(settings, ttsState, ttsActive, currentChapter),
                    ],
                  ),
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
                  ..._overlayWidgets(settings, ttsState, ttsActive, currentChapter),
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
          chapterName: currentChapter?.name ?? 'Chapter',
          onBack: () => Navigator.pop(context),
          onAddBookmark: _addBookmark,
          onShowBookmarks: _showBookmarks,
        ),
      if (_showControls && !ttsActive)
        buildReaderBottomBar(
          onPrevious: _goToPreviousChapter,
          onNext: _goToNextChapter,
          onToggleTts: _toggleTts,
          onShowChapterList: _showChapterList,
          hasEpubToc: false,
          onShowEpubToc: () {},
          onTranslate: () {},
          onSettings: _showSettingsDialog,
        ),
      if (_showControls && !ttsActive) buildReaderProgressBar(_scrollProgress),
      if (ttsActive)
        buildTtsFloatingPlayer(
          ttsState: ttsState,
          onSkipBack: () => ref.read(ttsManagerProvider.notifier).skipBackward(),
          onTogglePause: () => ref.read(ttsManagerProvider.notifier).togglePause(),
          onStop: () => ref.read(ttsManagerProvider.notifier).stop(),
          onSkipNext: () => ref.read(ttsManagerProvider.notifier).skipForward(),
          onShowTranslateDialog: () => translate.showTranslateDialog(context, ref),
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
          Text(nav.error!, style: const TextStyle(color: AppTheme.kReaderTextDefault), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              ref.read(readerNavigationProvider(widget.novelId).notifier).loadChapters(widget.chapterId);
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
