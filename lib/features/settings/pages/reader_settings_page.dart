import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/tts/tts_manager.dart';
import '../../../core/tts/microsoft_tts_provider.dart';
import '../../../core/utils/logger.dart';
import '../../../theme/app_theme.dart';

const _tag = 'ReaderSettings';

// ═══════════════════════════════════════════════════════════
// Reader Settings State
// ═══════════════════════════════════════════════════════════

class ReaderSettings {
  final double fontSize;
  final String fontFamily;
  final double lineHeight;
  final double paddingH;
  final double paddingV;
  final String scrollMode;
  final String textAlignment;
  final double paragraphSpacing;
  final bool bionicReading;
  final bool showTime;
  final bool showBattery;
  final bool keepScreenOn;
  final bool selectableText;
  final bool ttsAutoScroll;
  final String orientation;
  final String readerTheme;

  const ReaderSettings({
    this.fontSize = 16.0,
    this.fontFamily = '',
    this.lineHeight = 1.6,
    this.paddingH = 24.0,
    this.paddingV = 24.0,
    this.scrollMode = 'continuous',
    this.textAlignment = 'justify',
    this.paragraphSpacing = 12.0,
    this.bionicReading = false,
    this.showTime = true,
    this.showBattery = true,
    this.keepScreenOn = true,
    this.selectableText = false,
    this.ttsAutoScroll = true,
    this.orientation = 'auto',
    this.readerTheme = 'dark',
  });

  ReaderSettings copyWith({
    double? fontSize, String? fontFamily, double? lineHeight,
    double? paddingH, double? paddingV, String? scrollMode,
    String? textAlignment, double? paragraphSpacing, bool? bionicReading,
    bool? showTime, bool? showBattery, bool? keepScreenOn,
    bool? selectableText, bool? ttsAutoScroll, String? orientation, String? readerTheme,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: lineHeight ?? this.lineHeight,
      paddingH: paddingH ?? this.paddingH,
      paddingV: paddingV ?? this.paddingV,
      scrollMode: scrollMode ?? this.scrollMode,
      textAlignment: textAlignment ?? this.textAlignment,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      bionicReading: bionicReading ?? this.bionicReading,
      showTime: showTime ?? this.showTime,
      showBattery: showBattery ?? this.showBattery,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      selectableText: selectableText ?? this.selectableText,
      ttsAutoScroll: ttsAutoScroll ?? this.ttsAutoScroll,
      orientation: orientation ?? this.orientation,
      readerTheme: readerTheme ?? this.readerTheme,
    );
  }

  Color get bgColor {
    switch (readerTheme) {
      case 'light': return AppTheme.kReaderBgColors['light']!;
      case 'sepia': return AppTheme.kReaderBgColors['sepia']!;
      case 'green': return AppTheme.kReaderBgColors['green']!;
      case 'blue': return AppTheme.kReaderBgColors['blue']!;
      default: return AppTheme.kReaderBgDefault;
    }
  }

  Color get textColor {
    switch (readerTheme) {
      case 'light': return AppTheme.kReaderTextColors['light']!;
      case 'sepia': return AppTheme.kReaderTextColors['sepia']!;
      case 'green': return AppTheme.kReaderTextColors['green']!;
      case 'blue': return AppTheme.kReaderTextColors['blue']!;
      default: return AppTheme.kReaderTextDefault;
    }
  }
}

Future<List<String>> getSystemFonts() async {
  try {
    if (Platform.isLinux) {
      final result = await Process.run('fc-list', ['--format=%{family}\n']);
      if (result.exitCode == 0) {
        final seen = <String>{};
        final fonts = <String>[];
        for (final line in (result.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          for (final family in trimmed.split(',')) {
            final name = family.trim();
            if (name.isNotEmpty && seen.add(name.toLowerCase())) {
              fonts.add(name);
            }
          }
        }
        fonts.sort();
        return fonts;
      }
    }
    if (Platform.isWindows) {
      final result = await Process.run(
        'reg',
        ['query', 'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts', '/s'],
      );
      if (result.exitCode == 0) {
        final fonts = <String>{};
        final lines = (result.stdout as String).split('\n');
        for (final line in lines) {
          final match = RegExp(r'\((.+?)\)').firstMatch(line);
          if (match != null) fonts.add(match.group(1)!);
        }
        final sorted = fonts.toList()..sort();
        return sorted;
      }
    }
  } catch (e) {
    Log.e(_tag, 'Failed to get system fonts', e);
  }
  return ['Arial', 'Courier New', 'Georgia', 'Helvetica', 'Times New Roman',
    'Trebuchet MS', 'Verdana', 'Consolas', 'Lucida Console'];
}

class ReaderSettingsNotifier extends StateNotifier<ReaderSettings> {
  ReaderSettingsNotifier() : super(const ReaderSettings()) { _load(); }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = ReaderSettings(
        fontSize: p.getDouble('reader_font_size') ?? 16.0,
        fontFamily: p.getString('reader_font_family') ?? '',
        lineHeight: p.getDouble('reader_line_height') ?? 1.6,
        paddingH: p.getDouble('reader_padding_h') ?? 24.0,
        paddingV: p.getDouble('reader_padding_v') ?? 24.0,
        scrollMode: p.getString('reader_scroll_mode') ?? 'continuous',
        textAlignment: p.getString('reader_text_alignment') ?? 'justify',
        paragraphSpacing: p.getDouble('reader_paragraph_spacing') ?? 12.0,
        bionicReading: p.getBool('reader_bionic_reading') ?? false,
        showTime: p.getBool('reader_show_time') ?? true,
        showBattery: p.getBool('reader_show_battery') ?? true,
        keepScreenOn: p.getBool('reader_keep_screen_on') ?? true,
        selectableText: p.getBool('reader_selectable_text') ?? false,
        ttsAutoScroll: p.getBool('reader_tts_autoscroll') ?? true,
        orientation: p.getString('reader_orientation') ?? 'auto',
        readerTheme: p.getString('reader_theme') ?? 'dark',
      );
    } catch (e) {
      Log.e(_tag, 'Failed to load settings', e);
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('reader_font_size', state.fontSize);
      await p.setString('reader_font_family', state.fontFamily);
      await p.setDouble('reader_line_height', state.lineHeight);
      await p.setDouble('reader_padding_h', state.paddingH);
      await p.setDouble('reader_padding_v', state.paddingV);
      await p.setString('reader_scroll_mode', state.scrollMode);
      await p.setString('reader_text_alignment', state.textAlignment);
      await p.setDouble('reader_paragraph_spacing', state.paragraphSpacing);
      await p.setBool('reader_bionic_reading', state.bionicReading);
      await p.setBool('reader_show_time', state.showTime);
      await p.setBool('reader_show_battery', state.showBattery);
      await p.setBool('reader_keep_screen_on', state.keepScreenOn);
      await p.setBool('reader_selectable_text', state.selectableText);
      await p.setBool('reader_tts_autoscroll', state.ttsAutoScroll);
      await p.setString('reader_orientation', state.orientation);
      await p.setString('reader_theme', state.readerTheme);
    } catch (e) {
      Log.e(_tag, 'Failed to save settings', e);
    }
  }

  void _update(ReaderSettings Function(ReaderSettings) updater) {
    state = updater(state);
    _save();
  }

  void updateFontSize(double v) => _update((s) => s.copyWith(fontSize: v));
  void updateFontFamily(String v) => _update((s) => s.copyWith(fontFamily: v));
  void updateLineHeight(double v) => _update((s) => s.copyWith(lineHeight: v));
  void updatePaddingH(double v) => _update((s) => s.copyWith(paddingH: v));
  void updatePaddingV(double v) => _update((s) => s.copyWith(paddingV: v));
  void updateScrollMode(String v) => _update((s) => s.copyWith(scrollMode: v));
  void updateTextAlignment(String v) => _update((s) => s.copyWith(textAlignment: v));
  void updateParagraphSpacing(double v) => _update((s) => s.copyWith(paragraphSpacing: v));
  void updateOrientation(String v) => _update((s) => s.copyWith(orientation: v));
  void updateReaderTheme(String v) => _update((s) => s.copyWith(readerTheme: v));
  void toggleBionicReading() => _update((s) => s.copyWith(bionicReading: !s.bionicReading));
  void toggleShowTime() => _update((s) => s.copyWith(showTime: !s.showTime));
  void toggleShowBattery() => _update((s) => s.copyWith(showBattery: !s.showBattery));
  void toggleKeepScreenOn() => _update((s) => s.copyWith(keepScreenOn: !s.keepScreenOn));
  void toggleSelectableText() => _update((s) => s.copyWith(selectableText: !s.selectableText));
  void toggleTtsAutoScroll() => _update((s) => s.copyWith(ttsAutoScroll: !s.ttsAutoScroll));
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettings>((ref) {
  return ReaderSettingsNotifier();
});

// ═══════════════════════════════════════════════════════════
// Reader Settings Page — Tabbed (General + TTS)
// ═══════════════════════════════════════════════════════════

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
        body: const TabBarView(
          children: [
            _GeneralTab(),
            _TtsTab(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// General Tab — Font, Size, Layout, Display, Scroll, Theme
// ═══════════════════════════════════════════════════════════

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
        _section('Font'),
        _tile(
          title: 'Font Family',
          subtitle: settings.fontFamily.isEmpty ? 'System Default' : settings.fontFamily,
          onTap: () => _showFontPicker(context, settings, notifier),
        ),
        _slider('Size', settings.fontSize, 10, 30, '${settings.fontSize.round()} sp', (v) => notifier.updateFontSize(v)),
        _slider('Line Height', settings.lineHeight, 1.0, 3.0, settings.lineHeight.toStringAsFixed(1), (v) => notifier.updateLineHeight(v)),

        const SizedBox(height: 16),
        // ── Layout ──
        _section('Layout'),
        _slider('H Padding', settings.paddingH, 0, 50, '${settings.paddingH.round()}', (v) => notifier.updatePaddingH(v)),
        _slider('V Padding', settings.paddingV, 0, 50, '${settings.paddingV.round()}', (v) => notifier.updatePaddingV(v)),
        _slider('Paragraph Gap', settings.paragraphSpacing, 0, 40, '${settings.paragraphSpacing.round()}', (v) => notifier.updateParagraphSpacing(v)),

        const SizedBox(height: 16),
        // ── Text ──
        _section('Text'),
        _alignmentRow(settings, notifier),

        const SizedBox(height: 16),
        // ── Display ──
        _section('Display'),
        _switch('Bionic Reading', 'Bold first half of each word', settings.bionicReading, (_) => notifier.toggleBionicReading()),
        _switch('Selectable Text', null, settings.selectableText, (_) => notifier.toggleSelectableText()),
        _switch('Show Time', null, settings.showTime, (_) => notifier.toggleShowTime()),
        if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) ...[
          _switch('Show Battery', null, settings.showBattery, (_) => notifier.toggleShowBattery()),
          _switch('Keep Screen On', null, settings.keepScreenOn, (_) => notifier.toggleKeepScreenOn()),
        ],

        const SizedBox(height: 16),
        // ── Scroll ──
        _section('Scroll'),
        _radio('Continuous', 'continuous', settings.scrollMode, (v) => notifier.updateScrollMode(v!)),
        _radio('Paged', 'paged', settings.scrollMode, (v) => notifier.updateScrollMode(v!)),

        if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) ...[
          const SizedBox(height: 16),
          _section('Orientation'),
          _radio('Auto', 'auto', settings.orientation, (v) => notifier.updateOrientation(v!)),
          _radio('Portrait', 'portrait', settings.orientation, (v) => notifier.updateOrientation(v!)),
          _radio('Landscape', 'landscape', settings.orientation, (v) => notifier.updateOrientation(v!)),
        ],

        const SizedBox(height: 16),
        // ── Theme ──
        _section('Theme'),
        _themeRow(settings, notifier),
      ],
    );
  }

  void _showFontPicker(BuildContext context, ReaderSettings settings, ReaderSettingsNotifier notifier) {
    getSystemFonts().then((fonts) {
      if (!context.mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.5, maxChildSize: 0.8, minChildSize: 0.3, expand: false,
          builder: (ctx, scrollController) => Column(
            children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('Select Font', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: fonts.length + 1,
                  itemBuilder: (ctx, index) {
                    if (index == 0) {
                      return ListTile(
                        leading: Icon(settings.fontFamily.isEmpty ? Icons.check_circle : Icons.circle_outlined, color: settings.fontFamily.isEmpty ? AppTheme.kPrimary : null),
                        title: const Text('System Default'),
                        onTap: () { notifier.updateFontFamily(''); Navigator.pop(ctx); },
                      );
                    }
                    final font = fonts[index - 1];
                    final isSelected = settings.fontFamily.toLowerCase() == font.toLowerCase();
                    return ListTile(
                      leading: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? AppTheme.kPrimary : null),
                      title: Text(font, style: TextStyle(fontFamily: font, fontSize: 16)),
                      onTap: () { notifier.updateFontFamily(font); Navigator.pop(ctx); },
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
}

// ═══════════════════════════════════════════════════════════
// TTS Tab — Speed, Pitch, Voice, Language
// ═══════════════════════════════════════════════════════════

class _TtsTab extends ConsumerWidget {
  const _TtsTab();

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
                Icon(Icons.record_voice_over, color: AppTheme.kPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Microsoft Edge TTS', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        'Neural voices, works on all platforms',
                        style: TextStyle(fontSize: 12, color: AppTheme.kTextSecondaryDark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        // ── Playback ──
        _section('Playback'),
        _slider('Speed', ttsState.speed, 0.5, 3.0, '${ttsState.speed.toStringAsFixed(1)}x', (v) => ttsNotifier.updateSpeed(v)),
        _slider('Pitch', ttsState.pitch, 0.5, 2.0, ttsState.pitch.toStringAsFixed(1), (v) => ttsNotifier.updatePitch(v)),

        const SizedBox(height: 16),
        // ── Voice ──
        _section('Voice'),
        _tile(
          title: 'Language',
          subtitle: _languageName(ttsState.language),
          onTap: () => _showLanguagePicker(context, ref),
        ),
        _tile(
          title: 'Voice',
          subtitle: ttsState.voice.isEmpty ? 'Default (Brian)' : ttsState.voice,
          onTap: () => _showVoicePicker(context, ref),
        ),

        const SizedBox(height: 16),
        // ── Highlight ──
        _section('Read-along Highlight'),
        _radioTts('Paragraph', TtsHighlightMode.paragraph, ttsState.highlightMode, (v) => ttsNotifier.updateHighlightMode(v)),
        _radioTts('Sentence', TtsHighlightMode.sentence, ttsState.highlightMode, (v) => ttsNotifier.updateHighlightMode(v)),
        _radioTts('Word', TtsHighlightMode.word, ttsState.highlightMode, (v) => ttsNotifier.updateHighlightMode(v)),
      ],
    );
  }

  String _languageName(String code) {
    const langs = {
      'en-US': 'English (US)', 'en-GB': 'English (UK)', 'ru-RU': 'Russian',
      'uk-UA': 'Ukrainian', 'es-ES': 'Spanish', 'fr-FR': 'French',
      'de-DE': 'German', 'it-IT': 'Italian', 'pt-BR': 'Portuguese',
      'zh-CN': 'Chinese', 'ja-JP': 'Japanese', 'ko-KR': 'Korean',
      'ar-SA': 'Arabic', 'hi-IN': 'Hindi', 'tr-TR': 'Turkish',
      'pl-PL': 'Polish', 'nl-NL': 'Dutch', 'sv-SE': 'Swedish',
    };
    return langs[code] ?? code;
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(ttsManagerProvider.notifier);
    final current = ref.read(ttsManagerProvider).language;

    const languages = [
      ('en-US', 'English (US)'), ('en-GB', 'English (UK)'), ('ru-RU', 'Russian'),
      ('uk-UA', 'Ukrainian'), ('es-ES', 'Spanish'), ('fr-FR', 'French'),
      ('de-DE', 'German'), ('it-IT', 'Italian'), ('pt-BR', 'Portuguese (Brazil)'),
      ('zh-CN', 'Chinese (Simplified)'), ('ja-JP', 'Japanese'), ('ko-KR', 'Korean'),
      ('ar-SA', 'Arabic'), ('hi-IN', 'Hindi'), ('tr-TR', 'Turkish'),
      ('pl-PL', 'Polish'), ('nl-NL', 'Dutch'), ('sv-SE', 'Swedish'),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5, maxChildSize: 0.8, minChildSize: 0.3, expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Select Language', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: languages.length,
                itemBuilder: (ctx, index) {
                  final (code, name) = languages[index];
                  final isSelected = current == code;
                  return ListTile(
                    leading: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? AppTheme.kPrimary : null),
                    title: Text(name),
                    subtitle: Text(code, style: const TextStyle(fontSize: 12)),
                    onTap: () { notifier.updateLanguage(code); Navigator.pop(ctx); },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showVoicePicker(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(ttsManagerProvider.notifier);
    final current = ref.read(ttsManagerProvider).voice;

    final voices = await notifier.getVoices();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _VoicePickerSheet(voices: voices, current: current, notifier: notifier),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Voice Picker with Search
// ═══════════════════════════════════════════════════════════

class _VoicePickerSheet extends StatefulWidget {
  final List<EdgeTtsVoice> voices;
  final String current;
  final TtsManager notifier;

  const _VoicePickerSheet({required this.voices, required this.current, required this.notifier});

  @override
  State<_VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<_VoicePickerSheet> {
  final _searchController = TextEditingController();
  final _tts = MicrosoftTtsProvider();
  String _query = '';
  String? _playingVoiceId;
  late String _selectedVoice;

  @override
  void initState() {
    super.initState();
    _selectedVoice = widget.current;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tts.dispose();
    super.dispose();
  }

  Future<void> _playSample(EdgeTtsVoice voice) async {
    if (_playingVoiceId == voice.id) {
      await _tts.stop();
      setState(() => _playingVoiceId = null);
      return;
    }
    await _tts.stop();
    setState(() => _playingVoiceId = voice.id);
    await _tts.setVoice(voice.id);
    await _tts.speak(
      'Hello! This is a sample of the ${voice.name} voice. You can use this voice for reading novels.',
      speed: 1.0,
      pitch: 1.0,
    );
    if (mounted) setState(() => _playingVoiceId = null);
  }

  List<EdgeTtsVoice> get _filtered {
    if (_query.isEmpty) return widget.voices;
    final q = _query.toLowerCase();
    return widget.voices.where((v) =>
      v.name.toLowerCase().contains(q) ||
      v.language.toLowerCase().contains(q) ||
      v.id.toLowerCase().contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.7, maxChildSize: 0.9, minChildSize: 0.3, expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Select Voice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search voices...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () { _searchController.clear(); setState(() => _query = ''); },
                    )
                  : null,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${filtered.length} voices', style: TextStyle(fontSize: 11, color: AppTheme.kTextSecondaryDark)),
          ),
          const Divider(height: 1),
          // Default option
          ListTile(
            dense: true,
            leading: Icon(_selectedVoice.isEmpty ? Icons.check_circle : Icons.circle_outlined,
                color: _selectedVoice.isEmpty ? AppTheme.kPrimary : null),
            title: const Text('Default (Brian)'),
            onTap: () {
              widget.notifier.updateVoice('');
              setState(() => _selectedVoice = '');
              Navigator.pop(ctx);
            },
          ),
          const Divider(height: 1),
          // Voice list
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: filtered.length,
              itemBuilder: (ctx, index) {
                final voice = filtered[index];
                final isSelected = _selectedVoice == voice.id;
                final isPlaying = _playingVoiceId == voice.id;
                return ListTile(
                  dense: true,
                  leading: Icon(isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected ? AppTheme.kPrimary : null),
                  title: Text(voice.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${voice.language} · ${voice.gender ?? ""}', style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: Icon(isPlaying ? Icons.stop_circle : Icons.play_circle_outline,
                        color: isPlaying ? AppTheme.kPrimary : AppTheme.kTextSecondaryDark),
                    tooltip: isPlaying ? 'Stop sample' : 'Play sample',
                    onPressed: () => _playSample(voice),
                  ),
                  onTap: () {
                    widget.notifier.updateVoice(voice.id);
                    setState(() => _selectedVoice = voice.id);
                    Navigator.pop(ctx);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Shared Helpers
// ═══════════════════════════════════════════════════════════

Widget _section(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.kPrimary)),
  );
}

Widget _tile({required String title, String? subtitle, VoidCallback? onTap}) {
  return ListTile(
    dense: true, contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}

Widget _slider(String label, double value, double min, double max, String display, ValueChanged<double> onChanged) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13))),
      Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
      SizedBox(width: 50, child: Text(display, style: const TextStyle(fontSize: 12))),
    ]),
  );
}

Widget _switch(String title, String? subtitle, bool value, ValueChanged<bool> onChanged) {
  return SwitchListTile(
    dense: true, contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 11)) : null,
    value: value,
    onChanged: onChanged,
  );
}

Widget _radio(String title, String value, String groupValue, ValueChanged<String?> onChanged) {
  return RadioListTile<String>(
    dense: true, contentPadding: EdgeInsets.zero,
    title: Text(title), value: value, groupValue: groupValue, onChanged: onChanged,
  );
}

Widget _radioTts(String title, TtsHighlightMode value, TtsHighlightMode groupValue, ValueChanged<TtsHighlightMode> onChanged) {
  return ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      value == groupValue ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      color: value == groupValue ? AppTheme.kPrimary : AppTheme.kTextSecondaryDark,
      size: 20,
    ),
    title: Text(title, style: const TextStyle(fontSize: 14)),
    onTap: () => onChanged(value),
  );
}
