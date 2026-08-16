import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/tts/tts_manager.dart';
import '../../../theme/app_theme.dart';

/// Top bar with back button, chapter title, and bookmark icons.
Widget buildReaderTopBar({
  required BuildContext context,
  required String chapterName,
  required VoidCallback onBack,
  required VoidCallback onAddBookmark,
  required VoidCallback onShowBookmarks,
}) {
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
                onPressed: () { SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); onBack(); },
              ),
              Expanded(
                child: Text(
                  chapterName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.bookmark_border, color: Colors.white),
                onPressed: onAddBookmark,
              ),
              IconButton(
                icon: const Icon(Icons.bookmarks, color: Colors.white),
                onPressed: onShowBookmarks,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Bottom bar with navigation, TTS, chapter list, and settings buttons.
Widget buildReaderBottomBar({
  required VoidCallback onPrevious,
  required VoidCallback onNext,
  required VoidCallback onToggleTts,
  required VoidCallback onShowChapterList,
  required bool hasEpubToc,
  required VoidCallback onShowEpubToc,
  required VoidCallback onTranslate,
  required VoidCallback onSettings,
}) {
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
              IconButton(icon: const Icon(Icons.skip_previous, color: Colors.white), onPressed: onPrevious),
              IconButton(
                icon: const Icon(Icons.record_voice_over, color: Colors.white),
                onPressed: onToggleTts,
              ),
              IconButton(icon: const Icon(Icons.list, color: Colors.white), onPressed: onShowChapterList),
              if (hasEpubToc)
                IconButton(icon: const Icon(Icons.menu_book, color: Colors.white), onPressed: onShowEpubToc, tooltip: 'Table of Contents'),
              IconButton(icon: const Icon(Icons.translate, color: Colors.white), onPressed: onTranslate, tooltip: 'Translate'),
              IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: onSettings),
              IconButton(icon: const Icon(Icons.skip_next, color: Colors.white), onPressed: onNext),
            ],
          ),
        ),
      ),
    ),
  );
}

/// TTS floating player controls.
Widget buildTtsFloatingPlayer({
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
    bottom: 0, left: 0, right: 0,
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black54, Colors.transparent]),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: onSkipBack,
                  ),
                  IconButton(
                    icon: Icon(
                      ttsState.isPaused ? Icons.play_arrow : Icons.pause,
                      color: ttsState.isPaused ? Colors.white : AppTheme.kPrimary,
                    ),
                    onPressed: onTogglePause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop, color: Colors.white),
                    onPressed: onStop,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: onSkipNext,
                  ),
                ],
              ),
            ),
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

/// Thin progress bar at the top of the screen.
Widget buildReaderProgressBar(double scrollProgress) {
  return Positioned(
    top: 0, left: 0, right: 0,
    child: LinearProgressIndicator(
      value: scrollProgress,
      backgroundColor: Colors.white24,
      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.kPrimary),
      minHeight: 2,
    ),
  );
}
