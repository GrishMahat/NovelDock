import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tts/tts_manager.dart';
import '../theme/app_theme.dart';

/// Persistent mini player bar shown at the top when TTS is active.
class TtsMiniPlayer extends ConsumerWidget {
  const TtsMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(ttsManagerProvider);

    if (!ttsState.isSpeaking && !ttsState.isPaused) {
      return const SizedBox.shrink();
    }

    final ttsNotifier = ref.read(ttsManagerProvider.notifier);
    final progress = ttsState.totalLines > 0
        ? ttsState.currentLineIndex / ttsState.totalLines
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.kSurfaceVariantDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  // Pause/Play
                  IconButton(
                    icon: Icon(
                      ttsState.isPaused ? Icons.play_arrow : Icons.pause,
                      color: AppTheme.kPrimary,
                      size: 28,
                    ),
                    onPressed: () => ttsNotifier.togglePause(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36),
                  ),
                  const SizedBox(width: 4),
                  // Skip back
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 22),
                    onPressed: () => ttsNotifier.skipBackward(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32),
                  ),
                  // Skip forward
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 22),
                    onPressed: () => ttsNotifier.skipForward(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32),
                  ),
                  const SizedBox(width: 8),
                  // Current line info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ttsState.currentText.isNotEmpty
                              ? ttsState.currentText
                              : 'Playing...',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.kTextSecondaryDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${ttsState.currentLineIndex + 1} / ${ttsState.totalLines}',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Stop
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => ttsNotifier.stop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32),
                  ),
                ],
              ),
            ),
            // Progress bar
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.kPrimary),
              minHeight: 2,
            ),
          ],
        ),
      ),
    );
  }
}
