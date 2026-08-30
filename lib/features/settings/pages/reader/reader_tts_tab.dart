import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tts/engine/system_tts_engine.dart';
import '../../../../core/tts/tts_manager.dart';
import '../reader_helpers.dart';
import 'reader_settings_state.dart';
import 'tts_voice_picker.dart';

class TtsTab extends ConsumerWidget {
  const TtsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(ttsManagerProvider);
    final ttsNotifier = ref.read(ttsManagerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Engine info ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.record_voice_over,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Microsoft Edge TTS',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Neural voices, works on all platforms',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── Engine ──
        if (SystemTtsEngine.isSupported) ...[
          section(context, 'Voice engine'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'edge',
                label: Text('Microsoft'),
                icon: Icon(Icons.cloud_outlined),
              ),
              ButtonSegment(
                value: 'system',
                label: Text('On device'),
                icon: Icon(Icons.phone_android),
              ),
            ],
            selected: {ttsState.engineId},
            onSelectionChanged: (selection) {
              unawaited(ttsNotifier.setTtsEngine(selection.first));
            },
          ),
          Text(
            ttsState.engineId == 'system'
                ? 'Uses the voices installed on this device.'
                : 'Streams natural voices from Microsoft servers.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],

        const SizedBox(height: 16),

        // ── Playback ──
        section(context, 'Playback'),

        slider(
          context,
          'Speed',
          ttsState.speed,
          0.5,
          3.0,
          '${ttsState.speed.toStringAsFixed(1)}x',
          (value) {
            unawaited(ttsNotifier.updateSpeed(value));
          },
        ),

        slider(
          context,
          'Pitch',
          ttsState.pitch,
          0.5,
          2.0,
          ttsState.pitch.toStringAsFixed(1),
          (value) {
            unawaited(ttsNotifier.updatePitch(value));
          },
        ),

        const SizedBox(height: 16),

        // ── Voice ──
        section(context, 'Voice'),

        tile(
          context,
          title: 'Language',
          subtitle: ttsLanguageName(ttsState.language),
          onTap: () => showTtsLanguagePicker(context, ref),
        ),

        tile(
          context,
          title: 'Voice',
          subtitle: ttsState.voice.isEmpty
              ? (ttsState.engineId == 'system'
                    ? 'Device default'
                    : 'Default (Brian)')
              : ttsState.voice,
          onTap: () => showTtsVoicePicker(context, ref),
        ),

        const SizedBox(height: 16),

        // ── Highlight ──
        section(context, 'Read-along Highlight'),

        radioTts(
          context,
          'Paragraph',
          TtsHighlightMode.paragraph,
          ttsState.highlightMode,
          (value) {
            unawaited(ttsNotifier.updateHighlightMode(value));
          },
        ),

        radioTts(
          context,
          'Sentence',
          TtsHighlightMode.sentence,
          ttsState.highlightMode,
          (value) {
            unawaited(ttsNotifier.updateHighlightMode(value));
          },
        ),

        radioTts(
          context,
          'Word',
          TtsHighlightMode.word,
          ttsState.highlightMode,
          (value) {
            unawaited(ttsNotifier.updateHighlightMode(value));
          },
        ),

        const SizedBox(height: 16),

        // ── While listening ──
        section(context, 'While listening'),

        switchTile(
          context,
          'Auto-scroll while listening',
          'Keep the page following the spoken text',
          ref.watch(readerSettingsProvider).ttsAutoScroll,
          (_) =>
              ref.read(readerSettingsProvider.notifier).toggleTtsAutoScroll(),
        ),

        switchTile(
          context,
          'Auto-advance chapters',
          'Keep listening into the next chapter when one finishes',
          ref.watch(readerSettingsProvider).ttsAutoAdvance,
          (_) =>
              ref.read(readerSettingsProvider.notifier).toggleTtsAutoAdvance(),
        ),
      ],
    );
  }
}
