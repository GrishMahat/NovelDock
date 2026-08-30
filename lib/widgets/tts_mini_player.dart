import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tts/tts_manager.dart';
import '../theme/tokens.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final progress = ttsState.totalLines > 0
        ? ttsState.currentLineIndex / ttsState.totalLines
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.md,
                vertical: Insets.xs,
              ),
              child: Row(
                children: [
                  // Skip back
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, size: 22),
                    color: scheme.onSurfaceVariant,
                    tooltip: 'Previous line',
                    onPressed: () => ttsNotifier.skipBackward(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44),
                  ),
                  // Focal control: filled disc follows the live accent.
                  IconButton.filledTonal(
                    icon: Icon(
                      ttsState.isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 26,
                    ),
                    tooltip: ttsState.isPaused ? 'Play' : 'Pause',
                    onPressed: () => ttsNotifier.togglePause(),
                  ),
                  // Skip forward
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 22),
                    color: scheme.onSurfaceVariant,
                    tooltip: 'Next line',
                    onPressed: () => ttsNotifier.skipForward(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44),
                  ),
                  // Stop is destructive-adjacent; a hairline separates it
                  // from the transport cluster.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
                    child: SizedBox(
                      height: 22,
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: scheme.outlineVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.stop_rounded, size: 22),
                    color: scheme.onSurfaceVariant,
                    tooltip: 'Stop',
                    onPressed: () => ttsNotifier.stop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 44),
                  ),
                  const SizedBox(width: Insets.sm),
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
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${ttsState.currentLineIndex + 1} / ${ttsState.totalLines}',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Progress bar
            LinearProgressIndicator(
              value: progress,
              backgroundColor: scheme.outlineVariant,
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
              minHeight: 2,
            ),
          ],
        ),
      ),
    );
  }
}
