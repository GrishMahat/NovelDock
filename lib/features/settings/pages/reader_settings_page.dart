import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
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
        // ── Font ──
        section('Font'),
        tile(
          title: 'Font Family',
          subtitle: settings.fontFamily.isEmpty
              ? kDefaultReaderFont
              : settings.fontFamily,
          onTap: () => _showFontPicker(context, settings, notifier),
        ),
        slider(
          'Size',
          settings.fontSize,
          10,
          30,
          '${settings.fontSize.round()} sp',
          (v) => notifier.updateFontSize(v),
        ),
        slider(
          'Line Height',
          settings.lineHeight,
          1.0,
          3.0,
          settings.lineHeight.toStringAsFixed(1),
          (v) => notifier.updateLineHeight(v),
        ),

        const SizedBox(height: 16),
        // ── Layout ──
        section('Layout'),
        slider(
          'H Padding',
          settings.paddingH,
          0,
          50,
          '${settings.paddingH.round()}',
          (v) => notifier.updatePaddingH(v),
        ),
        slider(
          'V Padding',
          settings.paddingV,
          0,
          50,
          '${settings.paddingV.round()}',
          (v) => notifier.updatePaddingV(v),
        ),
        slider(
          'Paragraph Gap',
          settings.paragraphSpacing,
          0,
          40,
          '${settings.paragraphSpacing.round()}',
          (v) => notifier.updateParagraphSpacing(v),
        ),

        const SizedBox(height: 16),
        // ── Text ──
        section('Text'),
        _alignmentRow(settings, notifier),

        const SizedBox(height: 16),
        // ── Display ──
        section('Display'),
        switchTile(
          'Bionic Reading',
          'Bold first half of each word',
          settings.bionicReading,
          (_) => notifier.toggleBionicReading(),
        ),
        switchTile(
          'Selectable Text',
          null,
          settings.selectableText,
          (_) => notifier.toggleSelectableText(),
        ),
        switchTile(
          'Show Time',
          null,
          settings.showTime,
          (_) => notifier.toggleShowTime(),
        ),
        if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) ...[
          switchTile(
            'Show Battery',
            null,
            settings.showBattery,
            (_) => notifier.toggleShowBattery(),
          ),
          switchTile(
            'Keep Screen On',
            null,
            settings.keepScreenOn,
            (_) => notifier.toggleKeepScreenOn(),
          ),
        ],

        const SizedBox(height: 16),
        // ── Scroll ──
        section('Scroll'),
        RadioGroup<String>(
          groupValue: settings.scrollMode,
          onChanged: (v) => notifier.updateScrollMode(v!),
          child: Column(
            children: [
              radio(
                'Continuous',
                'continuous',
                () => notifier.updateScrollMode('continuous'),
              ),
              radio('Paged', 'paged', () => notifier.updateScrollMode('paged')),
            ],
          ),
        ),

        if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) ...[
          const SizedBox(height: 16),
          section('Orientation'),
          RadioGroup<String>(
            groupValue: settings.orientation,
            onChanged: (v) => notifier.updateOrientation(v!),
            child: Column(
              children: [
                radio('Auto', 'auto', () => notifier.updateOrientation('auto')),
                radio(
                  'Portrait',
                  'portrait',
                  () => notifier.updateOrientation('portrait'),
                ),
                radio(
                  'Landscape',
                  'landscape',
                  () => notifier.updateOrientation('landscape'),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),
        // ── Theme ──
        section('Theme'),
        _themeRow(settings, notifier),

        const SizedBox(height: 16),
        // ── Tap Zones ──
        section('Tap Zones'),
        _tapZoneRow(
          'Left',
          settings.leftTapAction,
          (v) => notifier.updateLeftTapAction(v!),
        ),
        _tapZoneRow(
          'Center',
          settings.centerTapAction,
          (v) => notifier.updateCenterTapAction(v!),
        ),
        _tapZoneRow(
          'Right',
          settings.rightTapAction,
          (v) => notifier.updateRightTapAction(v!),
        ),
      ],
    );
  }

  void _showFontPicker(
    BuildContext context,
    ReaderSettings settings,
    ReaderSettingsNotifier notifier,
  ) {
    getSystemFonts().then((fonts) {
      if (!context.mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.8,
          minChildSize: 0.3,
          expand: false,
          builder: (ctx, scrollController) => Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Select Font',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: fonts.length + 1,
                  itemBuilder: (ctx, index) {
                    if (index == 0) {
                      final isDefault =
                          settings.fontFamily.isEmpty ||
                          settings.fontFamily == kDefaultReaderFont;
                      return ListTile(
                        leading: Icon(
                          isDefault
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: isDefault ? AppTheme.kPrimary : null,
                        ),
                        title: Text(
                          kDefaultReaderFont,
                          style: const TextStyle(
                            fontFamily: kDefaultReaderFont,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: const Text('Bundled default'),
                        onTap: () {
                          notifier.updateFontFamily(kDefaultReaderFont);
                          Navigator.pop(ctx);
                        },
                      );
                    }
                    final font = fonts[index - 1];
                    final isSelected =
                        settings.fontFamily.toLowerCase() == font.toLowerCase();
                    return ListTile(
                      leading: Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? AppTheme.kPrimary : null,
                      ),
                      title: Text(
                        font,
                        style: TextStyle(fontFamily: font, fontSize: 16),
                      ),
                      onTap: () {
                        notifier.updateFontFamily(font);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    });
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
                    ? AppTheme.kPrimary
                    : Colors.grey.withValues(alpha: 0.3),
                width: isSelected ? 3 : 1,
              ),
            ),
            child: Center(
              child: Text(
                'Aa',
                style: TextStyle(
                  color: text,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isSelected ? AppTheme.kPrimary : null,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
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
        const SizedBox(
          width: 80,
          child: Text('Align', style: TextStyle(fontSize: 13)),
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

  Widget _tapZoneRow(
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
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'previous',
                  label: Text('Prev', style: TextStyle(fontSize: 11)),
                ),
                ButtonSegment(
                  value: 'menu',
                  label: Text('Menu', style: TextStyle(fontSize: 11)),
                ),
                ButtonSegment(
                  value: 'next',
                  label: Text('Next', style: TextStyle(fontSize: 11)),
                ),
                ButtonSegment(
                  value: 'none',
                  label: Text('Off', style: TextStyle(fontSize: 11)),
                ),
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
