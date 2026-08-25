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
        section(context, 'Font'),
        tile(
          context,
          title: 'Font Family',
          subtitle: settings.fontFamily.isEmpty
              ? kDefaultReaderFont
              : settings.fontFamily,
          onTap: () => _showFontPicker(context, settings, notifier),
        ),
        slider(
        context,
          'Size',
          settings.fontSize,
          10,
          30,
          '${settings.fontSize.round()} sp',
          (v) => notifier.updateFontSize(v),
        ),
        slider(
        context,
          'Line Height',
          settings.lineHeight,
          1.0,
          3.0,
          settings.lineHeight.toStringAsFixed(1),
          (v) => notifier.updateLineHeight(v),
        ),

        const SizedBox(height: 16),
        // ── Layout ──
        section(context, 'Layout'),
        slider(
        context,
          'H Padding',
          settings.paddingH,
          0,
          50,
          '${settings.paddingH.round()}',
          (v) => notifier.updatePaddingH(v),
        ),
        slider(
        context,
          'V Padding',
          settings.paddingV,
          0,
          50,
          '${settings.paddingV.round()}',
          (v) => notifier.updatePaddingV(v),
        ),
        slider(
        context,
          'Paragraph Gap',
          settings.paragraphSpacing,
          0,
          40,
          '${settings.paragraphSpacing.round()}',
          (v) => notifier.updateParagraphSpacing(v),
        ),

        const SizedBox(height: 16),
        // ── Text ──
        section(context, 'Text'),
        _alignmentRow(context, settings, notifier),

        const SizedBox(height: 16),
        // ── Display ──
        section(context, 'Display'),
        switchTile(
        context,
          'Bionic Reading',
          'Bold first half of each word',
          settings.bionicReading,
          (_) => notifier.toggleBionicReading(),
        ),
        switchTile(
        context,
          'Selectable Text',
          null,
          settings.selectableText,
          (_) => notifier.toggleSelectableText(),
        ),
        switchTile(
        context,
          'Show Time',
          null,
          settings.showTime,
          (_) => notifier.toggleShowTime(),
        ),
        if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) ...[
          switchTile(
        context,
            'Show Battery',
            null,
            settings.showBattery,
            (_) => notifier.toggleShowBattery(),
          ),
          switchTile(
        context,
            'Keep Screen On',
            null,
            settings.keepScreenOn,
            (_) => notifier.toggleKeepScreenOn(),
          ),
        ],

        const SizedBox(height: 16),
        // ── Scroll ──
        section(context, 'Scroll'),
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
          section(context, 'Orientation'),
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
        section(context, 'Theme'),
        _themeRow(context, settings, notifier),

        const SizedBox(height: 16),
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
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select Font',
                  style: Theme.of(ctx).textTheme.titleLarge,
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
                          color: isDefault
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          kDefaultReaderFont,
                          style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                            fontFamily: kDefaultReaderFont,
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
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        font,
                        style: TextStyle(
                          fontFamily: font,
                          fontSize:
                              Theme.of(context).textTheme.bodyLarge?.fontSize,
                        ),
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

  Widget _themeRow(
    BuildContext context,
    ReaderSettings settings,
    ReaderSettingsNotifier notifier,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _themeCircle(context,
          'Dark',
          'dark',
          AppTheme.kReaderBgDefault,
          AppTheme.kReaderTextDefault,
          settings,
          notifier,
        ),
        _themeCircle(context,
          'Light',
          'light',
          AppTheme.kReaderBgColors['light']!,
          AppTheme.kReaderTextColors['light']!,
          settings,
          notifier,
        ),
        _themeCircle(context,
          'Sepia',
          'sepia',
          AppTheme.kReaderBgColors['sepia']!,
          AppTheme.kReaderTextColors['sepia']!,
          settings,
          notifier,
        ),
        _themeCircle(context,
          'Green',
          'green',
          AppTheme.kReaderBgColors['green']!,
          AppTheme.kReaderTextColors['green']!,
          settings,
          notifier,
        ),
        _themeCircle(context,
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
    BuildContext context,
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
              color: isSelected ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _alignmentRow(
    BuildContext context,
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
