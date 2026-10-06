import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/tokens.dart';
import 'reader/reader_settings_state.dart';
import 'reader/reader_tts_tab.dart';
import 'reader_helpers.dart';

export 'reader/reader_settings_state.dart';

class ReaderSettingsPage extends ConsumerWidget {
  const ReaderSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reader Settings'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'General', icon: Icon(Icons.text_fields, size: 20)),
              Tab(text: 'TTS', icon: Icon(Icons.record_voice_over, size: 20)),
            ],
          ),
        ),
        body: const TabBarView(children: [_GeneralTab(), TtsTab()]),
      ),
    );
  }
}

class _GeneralTab extends ConsumerWidget {
  const _GeneralTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...readingSections(context, settings, notifier),
        const SizedBox(height: Insets.lg),
        // ── Tap Zones ──
        section(context, 'Tap Zones'),
        _tapZoneRow(
          context,
          'Left',
          settings.leftTapAction,
          (v) => notifier.updateLeftTapAction(v!),
        ),
        _tapZoneRow(
          context,
          'Center',
          settings.centerTapAction,
          (v) => notifier.updateCenterTapAction(v!),
        ),
        _tapZoneRow(
          context,
          'Right',
          settings.rightTapAction,
          (v) => notifier.updateRightTapAction(v!),
        ),
      ],
    );
  }

  Widget _tapZoneRow(
    BuildContext context,
    String label,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'previous', label: Text('Prev')),
                ButtonSegment(value: 'menu', label: Text('Menu')),
                ButtonSegment(value: 'next', label: Text('Next')),
                ButtonSegment(value: 'none', label: Text('Off')),
              ],
              selected: {value},
              onSelectionChanged: (s) => onChanged(s.first),
            ),
          ),
        ],
      ),
    );
  }
}
