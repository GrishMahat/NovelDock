import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../settings/pages/reader/reader_settings_state.dart';

/// Inline reader settings bottom sheet, shown from reader controls.
class ReaderSettingsSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  const ReaderSettingsSheet({super.key, required this.scrollController});

  @override
  ConsumerState<ReaderSettingsSheet> createState() =>
      _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends ConsumerState<ReaderSettingsSheet> {
  List<String> _systemFonts = [];

  @override
  void initState() {
    super.initState();
    _loadFonts();
  }

  Future<void> _loadFonts() async {
    final fonts = await getSystemFonts();
    if (mounted) {
      setState(() {
        _systemFonts = fonts;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Reader Settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              _section('Font'),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Font Family'),
                subtitle: Text(
                  settings.fontFamily.isEmpty
                      ? kDefaultReaderFont
                      : settings.fontFamily,
                  style: TextStyle(
                    fontFamily: settings.fontFamily.isEmpty
                        ? kDefaultReaderFont
                        : settings.fontFamily,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showFontPicker(settings, notifier),
              ),
              const SizedBox(height: 12),
              _slider(
                'Size',
                settings.fontSize,
                10,
                30,
                '${settings.fontSize.round()} sp',
                (v) => notifier.updateFontSize(v),
              ),
              _slider(
                'Line Height',
                settings.lineHeight,
                1.0,
                3.0,
                settings.lineHeight.toStringAsFixed(1),
                (v) => notifier.updateLineHeight(v),
              ),

              const SizedBox(height: 16),
              _section('Layout'),
              _slider(
                'H Padding',
                settings.paddingH,
                0,
                50,
                '${settings.paddingH.round()}',
                (v) => notifier.updatePaddingH(v),
              ),
              _slider(
                'V Padding',
                settings.paddingV,
                0,
                50,
                '${settings.paddingV.round()}',
                (v) => notifier.updatePaddingV(v),
              ),
              _slider(
                'Paragraph Gap',
                settings.paragraphSpacing,
                0,
                40,
                '${settings.paragraphSpacing.round()}',
                (v) => notifier.updateParagraphSpacing(v),
              ),

              const SizedBox(height: 16),
              _section('Text'),
              _alignmentRow(settings, notifier),

              const SizedBox(height: 16),
              _section('Display'),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('TTS Auto-Scroll'),
                subtitle: const Text('Auto-scroll reader while TTS is reading'),
                value: settings.ttsAutoScroll,
                onChanged: (_) => notifier.toggleTtsAutoScroll(),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('TTS Auto-Advance'),
                subtitle: const Text(
                  'Automatically start next chapter when TTS finishes',
                ),
                value: settings.ttsAutoAdvance,
                onChanged: (_) => notifier.toggleTtsAutoAdvance(),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Bionic Reading'),
                subtitle: const Text('Bold first half of each word'),
                value: settings.bionicReading,
                onChanged: (_) => notifier.toggleBionicReading(),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Selectable Text'),
                value: settings.selectableText,
                onChanged: (_) => notifier.toggleSelectableText(),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Show Time'),
                value: settings.showTime,
                onChanged: (_) => notifier.toggleShowTime(),
              ),
              if (!Platform.isLinux &&
                  !Platform.isMacOS &&
                  !Platform.isWindows) ...[
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show Battery'),
                  value: settings.showBattery,
                  onChanged: (_) => notifier.toggleShowBattery(),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep Screen On'),
                  value: settings.keepScreenOn,
                  onChanged: (_) => notifier.toggleKeepScreenOn(),
                ),
              ],

              const SizedBox(height: 16),
              _section('Scroll'),
              RadioGroup<String>(
                groupValue: settings.scrollMode,
                onChanged: (v) => notifier.updateScrollMode(v!),
                child: Column(
                  children: [
                    _radioTile(
                      'Continuous',
                      'continuous',
                      () => notifier.updateScrollMode('continuous'),
                    ),
                    _radioTile(
                      'Paged',
                      'paged',
                      () => notifier.updateScrollMode('paged'),
                    ),
                  ],
                ),
              ),

              if (!Platform.isLinux &&
                  !Platform.isMacOS &&
                  !Platform.isWindows) ...[
                const SizedBox(height: 16),
                _section('Orientation'),
                RadioGroup<String>(
                  groupValue: settings.orientation,
                  onChanged: (v) => notifier.updateOrientation(v!),
                  child: Column(
                    children: [
                      _radioTile(
                        'Auto',
                        'auto',
                        () => notifier.updateOrientation('auto'),
                      ),
                      _radioTile(
                        'Portrait',
                        'portrait',
                        () => notifier.updateOrientation('portrait'),
                      ),
                      _radioTile(
                        'Landscape',
                        'landscape',
                        () => notifier.updateOrientation('landscape'),
                      ),
                    ],
                  ),
                ),
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

  void _showFontPicker(
    ReaderSettings settings,
    ReaderSettingsNotifier notifier,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Font',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _systemFonts.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final isDefault =
                        settings.fontFamily.isEmpty ||
                        settings.fontFamily == kDefaultReaderFont;
                    return ListTile(
                      leading: Icon(
                        isDefault ? Icons.check_circle : Icons.circle_outlined,
                        color: isDefault
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        kDefaultReaderFont,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(
                          fontFamily: kDefaultReaderFont,
                        ),
                      ),
                      subtitle: const Text('Bundled default'),
                      onTap: () {
                        notifier.updateFontFamily(kDefaultReaderFont);
                        Navigator.pop(context);
                      },
                    );
                  }
                  final font = _systemFonts[index - 1];
                  final isSelected =
                      settings.fontFamily.toLowerCase() == font.toLowerCase();
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      font,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(fontFamily: font),
                    ),
                    onTap: () {
                      notifier.updateFontFamily(font);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: Insets.sm),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    String display,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(display, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _alignmentRow(
    ReaderSettings settings,
    ReaderSettingsNotifier notifier,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text('Align', style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'left',
                icon: Icon(Icons.format_align_left, size: 18),
              ),
              ButtonSegment(
                value: 'center',
                icon: Icon(Icons.format_align_center, size: 18),
              ),
              ButtonSegment(
                value: 'right',
                icon: Icon(Icons.format_align_right, size: 18),
              ),
              ButtonSegment(
                value: 'justify',
                icon: Icon(Icons.format_align_justify, size: 18),
              ),
            ],
            selected: {settings.textAlignment},
            onSelectionChanged: (s) => notifier.updateTextAlignment(s.first),
          ),
        ),
      ],
    );
  }

  Widget _radioTile(String title, String value, VoidCallback onSelect) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Radio<String>(value: value),
      onTap: onSelect,
    );
  }

  Widget _themeRow(ReaderSettings settings, ReaderSettingsNotifier notifier) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _themeCircle(
          'Dark',
          'dark',
          AppTheme.kReaderBgDefault,
          AppTheme.kReaderTextDefault,
          settings,
          notifier,
        ),
        _themeCircle(
          'Light',
          'light',
          AppTheme.kReaderBgColors['light']!,
          AppTheme.kReaderTextColors['light']!,
          settings,
          notifier,
        ),
        _themeCircle(
          'Sepia',
          'sepia',
          AppTheme.kReaderBgColors['sepia']!,
          AppTheme.kReaderTextColors['sepia']!,
          settings,
          notifier,
        ),
        _themeCircle(
          'Green',
          'green',
          AppTheme.kReaderBgColors['green']!,
          AppTheme.kReaderTextColors['green']!,
          settings,
          notifier,
        ),
        _themeCircle(
          'Blue',
          'blue',
          AppTheme.kReaderBgColors['blue']!,
          AppTheme.kReaderTextColors['blue']!,
          settings,
          notifier,
        ),
      ],
    );
  }

  Widget _themeCircle(
    String label,
    String themeKey,
    Color bg,
    Color text,
    ReaderSettings settings,
    ReaderSettingsNotifier notifier,
  ) {
    final isSelected = settings.readerTheme == themeKey;
    return GestureDetector(
      onTap: () => notifier.updateReaderTheme(themeKey),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: Center(
              child: Text('Aa', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: text)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
