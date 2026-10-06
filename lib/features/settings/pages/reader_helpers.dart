import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../../core/tts/tts_manager.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import 'reader/reader_settings_state.dart';

Widget section(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: Insets.sm),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

Widget tile(
  BuildContext context, {
  required String title,
  String? subtitle,
  VoidCallback? onTap,
}) {
  return ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle != null
        ? Text(subtitle, style: Theme.of(context).textTheme.bodySmall)
        : null,
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}

Widget slider(
  BuildContext context,
  String label,
  double value,
  double min,
  double max,
  String display,
  ValueChanged<double> onChanged,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
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
            label: display,
            semanticFormatterCallback: (_) => '$label $display',
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(display, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

Widget switchTile(
  BuildContext context,
  String title,
  String? subtitle,
  bool value,
  ValueChanged<bool> onChanged,
) {
  return SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle != null
        ? Text(subtitle, style: Theme.of(context).textTheme.bodySmall)
        : null,
    value: value,
    onChanged: onChanged,
  );
}

Widget radioTts(
  BuildContext context,
  String title,
  TtsHighlightMode value,
  TtsHighlightMode groupValue,
  ValueChanged<TtsHighlightMode> onChanged,
) {
  return ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      value == groupValue
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked,
      color: value == groupValue
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      size: 20,
    ),
    title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
    onTap: () => onChanged(value),
  );
}

// ─── Reader settings: the shared "Reading" surface ────────────────
//
// One body, two hosts: the settings page's General tab and the reader's
// inline sheet. The page appends its own Tap Zones section after this.

List<Widget> readingSections(
  BuildContext context,
  ReaderSettings settings,
  ReaderSettingsNotifier notifier,
) {
  return [
    // ── Font ──
    section(context, 'Font'),
    tile(
      context,
      title: 'Font Family',
      subtitle: settings.fontFamily.isEmpty
          ? kDefaultReaderFont
          : settings.fontFamily,
      onTap: () => showFontPicker(context, settings, notifier),
    ),
    slider(
      context,
      'Size',
      settings.effectiveFontSize,
      // Narrower range on phones: past ~22px the measure drops below a
      // readable line length at this width.
      settings.isCompactProfile ? 13 : 10,
      settings.isCompactProfile ? 24 : 30,
      '${settings.effectiveFontSize.round()}',
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

    const SizedBox(height: Insets.lg),
    // ── Layout ──
    section(context, 'Layout'),
    slider(
      context,
      'Side margins',
      settings.effectivePaddingH,
      0,
      settings.isCompactProfile ? 24 : 50,
      '${settings.effectivePaddingH.round()}',
      (v) => notifier.updatePaddingH(v),
    ),
    slider(
      context,
      'Top and bottom margins',
      settings.effectivePaddingV,
      0,
      settings.isCompactProfile ? 32 : 50,
      '${settings.effectivePaddingV.round()}',
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

    const SizedBox(height: Insets.lg),
    // ── Text ──
    section(context, 'Text'),
    alignmentRow(context, settings, notifier),

    const SizedBox(height: Insets.lg),
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
      'Show Author Notes',
      'Keep translator author-note blocks in chapters',
      settings.showAuthorNotes,
      (_) => notifier.toggleShowAuthorNotes(),
    ),
    switchTile(
      context,
      'Remove Bloat',
      'Strip translator and editor credit blocks',
      settings.removeBloat,
      (_) => notifier.toggleRemoveBloat(),
    ),
    if (Platform.isAndroid)
      switchTile(
        context,
        'Volume Key Scrolling',
        'Volume buttons turn pages instead of changing volume',
        settings.volumeScroll,
        (_) => notifier.toggleVolumeScroll(),
      ),
    if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows)
      switchTile(
        context,
        'Keep Screen On',
        null,
        settings.keepScreenOn,
        (_) => notifier.toggleKeepScreenOn(),
      ),

    const SizedBox(height: Insets.lg),
    // ── Theme ──
    section(context, 'Theme'),
    themeRow(context, settings, notifier),
  ];
}

/// Font list, resolved on open (a `fc-list`/registry scan is too slow to do
/// on every settings build, and only the picker needs it).
void showFontPicker(
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
              padding: const EdgeInsets.all(Insets.lg),
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
                        isDefault ? Icons.check_circle : Icons.circle_outlined,
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
                          ? Theme.of(ctx).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      font,
                      style: Theme.of(
                        ctx,
                      ).textTheme.bodyLarge?.copyWith(fontFamily: font),
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

Widget themeRow(
  BuildContext context,
  ReaderSettings settings,
  ReaderSettingsNotifier notifier,
) {
  return Wrap(
    spacing: Insets.md,
    runSpacing: Insets.sm,
    children: [
      themeCircle(
        context,
        'Dark',
        'dark',
        AppTheme.kReaderBgDefault,
        AppTheme.kReaderTextDefault,
        settings,
        notifier,
      ),
      themeCircle(
        context,
        'Light',
        'light',
        AppTheme.kReaderBgColors['light']!,
        AppTheme.kReaderTextColors['light']!,
        settings,
        notifier,
      ),
      themeCircle(
        context,
        'Sepia',
        'sepia',
        AppTheme.kReaderBgColors['sepia']!,
        AppTheme.kReaderTextColors['sepia']!,
        settings,
        notifier,
      ),
      themeCircle(
        context,
        'Green',
        'green',
        AppTheme.kReaderBgColors['green']!,
        AppTheme.kReaderTextColors['green']!,
        settings,
        notifier,
      ),
      themeCircle(
        context,
        'Blue',
        'blue',
        AppTheme.kReaderBgColors['blue']!,
        AppTheme.kReaderTextColors['blue']!,
        settings,
        notifier,
      ),
      themeCircle(
        context,
        'E-ink',
        'eink',
        AppTheme.kReaderBgColors['eink']!,
        AppTheme.kReaderTextColors['eink']!,
        settings,
        notifier,
      ),
    ],
  );
}

Widget themeCircle(
  BuildContext context,
  String label,
  String themeKey,
  Color bg,
  Color text,
  ReaderSettings settings,
  ReaderSettingsNotifier notifier,
) {
  final isSelected = settings.readerTheme == themeKey;
  return Semantics(
    button: true,
    selected: isSelected,
    label: '$label theme',
    child: GestureDetector(
      onTap: () => notifier.updateReaderTheme(themeKey),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
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
              child: Text(
                'Aa',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: text),
              ),
            ),
          ),
          const SizedBox(height: Insets.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isSelected ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget alignmentRow(
  BuildContext context,
  ReaderSettings settings,
  ReaderSettingsNotifier notifier,
) {
  return Row(
    children: [
      SizedBox(
        width: 80,
        child: Text('Alignment', style: Theme.of(context).textTheme.bodyMedium),
      ),
      Expanded(
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'left',
              icon: Icon(Icons.format_align_left, size: 18),
              tooltip: 'Align left',
            ),
            ButtonSegment(
              value: 'center',
              icon: Icon(Icons.format_align_center, size: 18),
              tooltip: 'Align center',
            ),
            ButtonSegment(
              value: 'right',
              icon: Icon(Icons.format_align_right, size: 18),
              tooltip: 'Align right',
            ),
            ButtonSegment(
              value: 'justify',
              icon: Icon(Icons.format_align_justify, size: 18),
              tooltip: 'Justify',
            ),
          ],
          selected: {settings.textAlignment},
          onSelectionChanged: (s) => notifier.updateTextAlignment(s.first),
        ),
      ),
    ],
  );
}
