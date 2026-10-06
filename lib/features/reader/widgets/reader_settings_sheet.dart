import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/tts/engine/system_tts_engine.dart';
import '../../../core/tts/tts_manager.dart';
import '../../../theme/tokens.dart';
import '../../settings/pages/reader/tts_voice_picker.dart';
import '../../settings/pages/reader/sleep_timer_sheet.dart';
import '../../settings/pages/reader_helpers.dart';
import '../../settings/pages/reader/reader_settings_state.dart';

/// Inline reader settings bottom sheet, shown from reader controls.
///
/// Two tabs: [Reading] (typography, layout, theme) and [Listen] (TTS engine,
/// playback, voice, read-along behavior). Adding a surface here — e.g.
/// Translation — only needs a new segment plus a section builder below.
class ReaderSettingsSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  const ReaderSettingsSheet({super.key, required this.scrollController});

  @override
  ConsumerState<ReaderSettingsSheet> createState() =>
      _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends ConsumerState<ReaderSettingsSheet> {
  static const _tabReading = 0;
  static const _tabListen = 1;

  int _sectionTab = _tabReading;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.lg,
            Insets.lg,
            Insets.sm,
          ),
          child: Text(
            'Reader Settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: _tabReading,
                label: Text('Reading'),
                icon: Icon(Icons.menu_book_outlined),
              ),
              ButtonSegment(
                value: _tabListen,
                label: Text('Listen'),
                icon: Icon(Icons.record_voice_over_outlined),
              ),
            ],
            selected: {_sectionTab},
            onSelectionChanged: (selection) {
              setState(() => _sectionTab = selection.first);
              if (widget.scrollController.hasClients) {
                widget.scrollController.jumpTo(0);
              }
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(Insets.lg),
            children: _sectionTab == _tabReading
                ? readingSections(context, settings, notifier)
                : _listenSections(),
          ),
        ),
      ],
    );
  }

  List<Widget> _listenSections() {
    final ttsState = ref.watch(ttsManagerProvider);
    final ttsNotifier = ref.read(ttsManagerProvider.notifier);
    final readerSettings = ref.watch(readerSettingsProvider);
    final readerNotifier = ref.read(readerSettingsProvider.notifier);

    return [
      // ── Voice engine ──
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
        const SizedBox(height: Insets.sm),
        Text(
          ttsState.engineId == 'system'
              ? 'Uses the voices installed on this device.'
              : 'Streams natural voices from Microsoft servers.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: Insets.lg),
      ],

      // ── Playback ──
      section(context, 'Playback'),
      slider(
        context,
        'Speed',
        ttsState.speed,
        0.5,
        3.0,
        '${ttsState.speed.toStringAsFixed(1)}x',
        (value) => unawaited(ttsNotifier.updateSpeed(value)),
      ),
      slider(
        context,
        'Pitch',
        ttsState.pitch,
        0.5,
        2.0,
        ttsState.pitch.toStringAsFixed(1),
        (value) => unawaited(ttsNotifier.updatePitch(value)),
      ),
      tile(
        context,
        title: 'Sleep timer',
        subtitle: describeSleepTimer(
          mode: ttsState.sleepTimerMode,
          minutes: ttsState.sleepMinutes,
          hour: ttsState.sleepHour,
          minute: ttsState.sleepMinute,
          endsAt: ttsState.sleepEndsAt,
          now: DateTime.now(),
        ),
        onTap: () => showSleepTimerSheet(context, ref),
      ),

      const SizedBox(height: Insets.lg),
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
        title: 'Choose voice',
        subtitle: ttsState.voice.isEmpty
            ? (ttsState.engineId == 'system'
                  ? 'Device default'
                  : 'Default voice')
            : ttsState.voice,
        onTap: () => showTtsVoicePicker(context, ref),
      ),

      const SizedBox(height: Insets.lg),
      // ── Read-along Highlight ──
      section(context, 'Read-along Highlight'),
      SegmentedButton<TtsHighlightMode>(
        segments: const [
          ButtonSegment(
            value: TtsHighlightMode.paragraph,
            label: Text('Paragraph'),
          ),
          ButtonSegment(
            value: TtsHighlightMode.sentence,
            label: Text('Sentence'),
          ),
        ],
        selected: {ttsState.highlightMode},
        onSelectionChanged: (selection) {
          unawaited(ttsNotifier.updateHighlightMode(selection.first));
        },
      ),

      const SizedBox(height: Insets.lg),
      // ── While listening ──
      section(context, 'While listening'),
      switchTile(
        context,
        'Auto-scroll while listening',
        'Keep the page following the spoken text',
        readerSettings.ttsAutoScroll,
        (_) => readerNotifier.toggleTtsAutoScroll(),
      ),
      switchTile(
        context,
        'Lock scrolling while listening',
        'Prevent manual scrolling while auto-scroll follows playback',
        readerSettings.ttsScrollLock,
        (_) {
          if (readerSettings.ttsAutoScroll) {
            readerNotifier.toggleTtsScrollLock();
          }
        },
      ),
      switchTile(
        context,
        'Auto-advance chapters',
        'Keep listening into the next chapter when one finishes',
        readerSettings.ttsAutoAdvance,
        (_) => readerNotifier.toggleTtsAutoAdvance(),
      ),
    ];
  }
}
