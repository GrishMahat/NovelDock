import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/tts/tts_manager.dart';
import '../../../theme/tokens.dart';
import '../../settings/pages/reader/reader_settings_state.dart';

/// Reader-theme surface color: text tinted over background, so chrome sits
/// well on every reader background (dark/light/sepia/green/blue).
Color _readerSurface(ReaderSettings s) => Color.alphaBlend(
    s.textColor.withValues(alpha: 0.08), s.bgColor);

BorderSide _readerHairline(ReaderSettings s) =>
    BorderSide(color: s.textColor.withValues(alpha: 0.18));

/// Entrance animation for reader chrome: short fade + slide, played once.
/// Respects MediaQuery.disableAnimationsOf.
class _ReaderEnter extends StatefulWidget {
  final bool entersFromTop;
  final Widget child;

  const _ReaderEnter({
    required this.entersFromTop,
    required this.child,
  });

  @override
  State<_ReaderEnter> createState() => _ReaderEnterState();
}

class _ReaderEnterState extends State<_ReaderEnter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this);
  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Motion.base;
    // Play the entrance once; skip replays on later dependency changes.
    if (_controller.status == AnimationStatus.dismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(
          begin: Offset(0, widget.entersFromTop ? -0.15 : 0.15),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Full-width top toolbar: back + chapter title pinned left, bookmark
/// actions right. Attached to the top edge with a hairline bottom border.
Widget buildReaderTopBar({
  required BuildContext context,
  required ReaderSettings settings,
  required String chapterName,
  required VoidCallback onBack,
  required VoidCallback onAddBookmark,
  required VoidCallback onShowBookmarks,
}) {
  final s = settings;
  return Positioned(
    top: 0, left: 0, right: 0,
    child: SafeArea(
      bottom: false,
      child: _ReaderEnter(
        entersFromTop: true,
        child: Material(
          color: _readerSurface(s),
          elevation: 0,
          child: IconTheme(
            data: IconThemeData(color: s.textColor),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back (Esc)',
                        onPressed: () {
                          SystemChrome.setEnabledSystemUIMode(
                              SystemUiMode.edgeToEdge);
                          onBack();
                        },
                      ),
                      const SizedBox(width: Insets.xs),
                      Expanded(
                        child: Text(
                          chapterName,
                          style: TextStyle(
                            color: s.textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.bookmark_border),
                        tooltip: 'Add bookmark',
                        onPressed: onAddBookmark,
                      ),
                      IconButton(
                        icon: const Icon(Icons.bookmarks),
                        tooltip: 'Bookmarks',
                        onPressed: onShowBookmarks,
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: _readerHairline(s).color),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Bottom bar: chapter navigation, TTS, chapter list, settings. Floating pill.
Widget buildReaderBottomBar({
  required ReaderSettings settings,
  required VoidCallback onPrevious,
  required VoidCallback onNext,
  required VoidCallback onToggleTts,
  required VoidCallback onShowChapterList,
  required VoidCallback onSettings,
}) {
  return Positioned(
    bottom: Insets.sm, left: 0, right: 0,
    child: SafeArea(
      top: false,
      child: Center(
        child: _ReaderEnter(
          entersFromTop: false,
          child: Material(
            color: _readerSurface(settings),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: _readerHairline(settings),
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: IconTheme(
              data: IconThemeData(color: settings.textColor),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous),
                      tooltip: 'Previous chapter (Left)',
                      onPressed: onPrevious,
                    ),
                    IconButton(
                      icon: const Icon(Icons.record_voice_over),
                      tooltip: 'Read aloud',
                      onPressed: onToggleTts,
                    ),
                    IconButton(
                      icon: const Icon(Icons.list),
                      tooltip: 'Chapter list',
                      onPressed: onShowChapterList,
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings),
                      tooltip: 'Reading settings',
                      onPressed: onSettings,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next),
                      tooltip: 'Next chapter (Right)',
                      onPressed: onNext,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// TTS floating player controls.
Widget buildTtsFloatingPlayer({
  required ReaderSettings settings,
  required TtsManagerState ttsState,
  required VoidCallback onSkipBack,
  required VoidCallback onTogglePause,
  required VoidCallback onStop,
  required VoidCallback onSkipNext,
}) {
  final progress = ttsState.totalChunks > 0
      ? ttsState.currentChunkIndex / ttsState.totalChunks
      : 0.0;

  return Positioned(
    bottom: Insets.sm, left: 0, right: 0,
    child: SafeArea(
      top: false,
      child: Center(
        child: _ReaderEnter(
          entersFromTop: false,
          child: Material(
            color: _readerSurface(settings),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: _readerHairline(settings),
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: IconTheme(
              data: IconThemeData(color: settings.textColor),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Insets.sm),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous),
                          tooltip: 'Previous paragraph',
                          onPressed: onSkipBack,
                        ),
                        IconButton(
                          icon: Icon(
                            ttsState.isPaused
                                ? Icons.play_arrow
                                : Icons.pause,
                          ),
                          tooltip: ttsState.isPaused ? 'Resume' : 'Pause',
                          onPressed: onTogglePause,
                        ),
                        IconButton(
                          icon: const Icon(Icons.stop),
                          tooltip: 'Stop',
                          onPressed: onStop,
                        ),
                        IconButton(
                          icon: const Icon(Icons.skip_next),
                          tooltip: 'Next paragraph',
                          onPressed: onSkipNext,
                        ),
                      ],
                    ),
                  ),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor:
                        settings.textColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        settings.textColor.withValues(alpha: 0.7)),
                    minHeight: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Thin reading-progress line at the very top of the screen.
Widget buildReaderProgressBar(double scrollProgress, ReaderSettings settings) {
  return Positioned(
    top: 0, left: 0, right: 0,
    child: LinearProgressIndicator(
      value: scrollProgress,
      backgroundColor: Colors.transparent,
      valueColor: AlwaysStoppedAnimation<Color>(
          settings.textColor.withValues(alpha: 0.55)),
      minHeight: 2,
    ),
  );
}
