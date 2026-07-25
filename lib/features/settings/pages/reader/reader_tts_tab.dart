import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tts/tts_manager.dart';
import '../../../../core/tts/microsoft_tts_provider.dart';
import '../../../../theme/app_theme.dart';
import '../reader_helpers.dart';

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
        section('Playback'),
        slider('Speed', ttsState.speed, 0.5, 3.0, '${ttsState.speed.toStringAsFixed(1)}x', (v) => ttsNotifier.updateSpeed(v)),
        slider('Pitch', ttsState.pitch, 0.5, 2.0, ttsState.pitch.toStringAsFixed(1), (v) => ttsNotifier.updatePitch(v)),

        const SizedBox(height: 16),
        // ── Voice ──
        section('Voice'),
        tile(
          title: 'Language',
          subtitle: _languageName(ttsState.language),
          onTap: () => _showLanguagePicker(context, ref),
        ),
        tile(
          title: 'Voice',
          subtitle: ttsState.voice.isEmpty ? 'Default (Brian)' : ttsState.voice,
          onTap: () => _showVoicePicker(context, ref),
        ),

        const SizedBox(height: 16),
        // ── Highlight ──
        section('Read-along Highlight'),
        radioTts('Paragraph', TtsHighlightMode.paragraph, ttsState.highlightMode, (v) => ttsNotifier.updateHighlightMode(v)),
        radioTts('Sentence', TtsHighlightMode.sentence, ttsState.highlightMode, (v) => ttsNotifier.updateHighlightMode(v)),
        radioTts('Word', TtsHighlightMode.word, ttsState.highlightMode, (v) => ttsNotifier.updateHighlightMode(v)),
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
