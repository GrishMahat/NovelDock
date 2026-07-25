import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../reader_screen.dart' show getSystemFonts;
import '../../settings/pages/reader/reader_settings_state.dart';

/// Inline reader settings bottom sheet — shown from reader controls.
class ReaderSettingsSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  const ReaderSettingsSheet({super.key, required this.scrollController});

  @override
  ConsumerState<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends ConsumerState<ReaderSettingsSheet> {
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
              _section('Font'),
              ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                title: const Text('Font Family'),
                subtitle: Text(settings.fontFamily.isEmpty ? 'System Default' : settings.fontFamily,
                    style: TextStyle(fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showFontPicker(settings, notifier),
              ),
              const SizedBox(height: 12),
              _slider('Size', settings.fontSize, 10, 30, '${settings.fontSize.round()} sp', (v) => notifier.updateFontSize(v)),
              _slider('Line Height', settings.lineHeight, 1.0, 3.0, settings.lineHeight.toStringAsFixed(1), (v) => notifier.updateLineHeight(v)),

              const SizedBox(height: 16),
              _section('Layout'),
              _slider('H Padding', settings.paddingH, 0, 50, '${settings.paddingH.round()}', (v) => notifier.updatePaddingH(v)),
              _slider('V Padding', settings.paddingV, 0, 50, '${settings.paddingV.round()}', (v) => notifier.updatePaddingV(v)),
              _slider('Paragraph Gap', settings.paragraphSpacing, 0, 40, '${settings.paragraphSpacing.round()}', (v) => notifier.updateParagraphSpacing(v)),

              const SizedBox(height: 16),
              _section('Text'),
              _alignmentRow(settings, notifier),

              const SizedBox(height: 16),
              _section('Display'),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('TTS Auto-Scroll'), subtitle: const Text('Auto-scroll reader while TTS is reading'), value: settings.ttsAutoScroll, onChanged: (_) => notifier.toggleTtsAutoScroll()),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('TTS Auto-Advance'), subtitle: const Text('Automatically start next chapter when TTS finishes'), value: settings.ttsAutoAdvance, onChanged: (_) => notifier.toggleTtsAutoAdvance()),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Bionic Reading'), subtitle: const Text('Bold first half of each word'), value: settings.bionicReading, onChanged: (_) => notifier.toggleBionicReading()),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Selectable Text'), value: settings.selectableText, onChanged: (_) => notifier.toggleSelectableText()),
              SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Show Time'), value: settings.showTime, onChanged: (_) => notifier.toggleShowTime()),
              if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) ...[
                SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Show Battery'), value: settings.showBattery, onChanged: (_) => notifier.toggleShowBattery()),
                SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Keep Screen On'), value: settings.keepScreenOn, onChanged: (_) => notifier.toggleKeepScreenOn()),
              ],

              const SizedBox(height: 16),
              _section('Scroll'),
              _radioTile('Continuous', 'continuous', settings.scrollMode, (v) => notifier.updateScrollMode(v!)),
              _radioTile('Paged', 'paged', settings.scrollMode, (v) => notifier.updateScrollMode(v!)),

              if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) ...[
                const SizedBox(height: 16),
                _section('Orientation'),
                _radioTile('Auto', 'auto', settings.orientation, (v) => notifier.updateOrientation(v!)),
                _radioTile('Portrait', 'portrait', settings.orientation, (v) => notifier.updateOrientation(v!)),
                _radioTile('Landscape', 'landscape', settings.orientation, (v) => notifier.updateOrientation(v!)),
              ],

              const SizedBox(height: 16),
              _section('Theme'),
              _themeRow(settings, notifier),
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

  Widget _section(String title) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.kTextSecondaryDark)));

  Widget _slider(String label, double value, double min, double max, String display, ValueChanged<double> onChanged) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13))),
      Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
      SizedBox(width: 40, child: Text(display, style: const TextStyle(fontSize: 12))),
    ]));
  }

  Widget _alignmentRow(ReaderSettings settings, ReaderSettingsNotifier notifier) {
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

  Widget _radioTile(String title, String value, String groupValue, ValueChanged<String?> onChanged) {
    return RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, title: Text(title), value: value, groupValue: groupValue, onChanged: onChanged);
  }

  Widget _themeRow(ReaderSettings settings, ReaderSettingsNotifier notifier) {
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
