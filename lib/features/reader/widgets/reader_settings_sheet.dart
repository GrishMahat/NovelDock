import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/tts/engine/system_tts_engine.dart';
import '../../../core/tts/tts_manager.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../settings/pages/reader/tts_voice_picker.dart';
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

  List<String> _systemFonts = [];
  int _sectionTab = _tabReading;

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
                ? _readingSections(context, settings, notifier)
                : _listenSections(),
          ),
        ),
      ],
    );
  }

  List<Widget> _readingSections(
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
        onTap: () => _showFontPicker(settings, notifier),
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

      const SizedBox(height: Insets.lg),
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

      const SizedBox(height: Insets.lg),
      // ── Text ──
      section(context, 'Text'),
      _alignmentRow(settings, notifier),

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

      const SizedBox(height: Insets.lg),
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
        const SizedBox(height: Insets.lg),
        // ── Orientation ──
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

      const SizedBox(height: Insets.lg),
      // ── Theme ──
      section(context, 'Theme'),
      _themeRow(settings, notifier),
    ];
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
                  : 'Default (Brian)')
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
          ButtonSegment(value: TtsHighlightMode.word, label: Text('Word')),
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
              padding: const EdgeInsets.all(Insets.lg),
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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

  Widget _themeRow(ReaderSettings settings, ReaderSettingsNotifier notifier) {
    return Wrap(
      spacing: Insets.md,
      runSpacing: Insets.sm,
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
    );
  }
}
