import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/tts/engine/edge_tts_engine.dart';
import '../../../../core/tts/engine/tts_engine.dart';
import '../../../../core/tts/tts_manager.dart';
import '../../../../core/tts/tts_player.dart';
import '../../../../core/tts/tts_stream_source.dart';
import '../../../../core/utils/logger.dart';
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
                      const Text(
                        'Microsoft Edge TTS',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Neural voices, works on all platforms',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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

        slider(
          'Speed',
          ttsState.speed,
          0.5,
          3.0,
          '${ttsState.speed.toStringAsFixed(1)}x',
          (value) {
            unawaited(ttsNotifier.updateSpeed(value));
          },
        ),

        slider(
          'Pitch',
          ttsState.pitch,
          0.5,
          2.0,
          ttsState.pitch.toStringAsFixed(1),
          (value) {
            unawaited(ttsNotifier.updatePitch(value));
          },
        ),

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

        radioTts(context,
          'Paragraph',
          TtsHighlightMode.paragraph,
          ttsState.highlightMode,
          (value) {
            if (value == null) return;

            unawaited(ttsNotifier.updateHighlightMode(value));
          },
        ),

        radioTts(context,
          'Sentence',
          TtsHighlightMode.sentence,
          ttsState.highlightMode,
          (value) {
            if (value == null) return;

            unawaited(ttsNotifier.updateHighlightMode(value));
          },
        ),

        radioTts(context, 'Word', TtsHighlightMode.word, ttsState.highlightMode, (
          value,
        ) {
          if (value == null) return;

          unawaited(ttsNotifier.updateHighlightMode(value));
        }),
      ],
    );
  }

  String _languageName(String code) {
    const languages = <String, String>{
      'en-US': 'English (US)',
      'en-GB': 'English (UK)',
      'ru-RU': 'Russian',
      'uk-UA': 'Ukrainian',
      'es-ES': 'Spanish',
      'fr-FR': 'French',
      'de-DE': 'German',
      'it-IT': 'Italian',
      'pt-BR': 'Portuguese',
      'zh-CN': 'Chinese',
      'ja-JP': 'Japanese',
      'ko-KR': 'Korean',
      'ar-SA': 'Arabic',
      'hi-IN': 'Hindi',
      'tr-TR': 'Turkish',
      'pl-PL': 'Polish',
      'nl-NL': 'Dutch',
      'sv-SE': 'Swedish',
    };

    return languages[code] ?? code;
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(ttsManagerProvider.notifier);

    final current = ref.read(ttsManagerProvider).language;

    const languages = <(String, String)>[
      ('en-US', 'English (US)'),
      ('en-GB', 'English (UK)'),
      ('ru-RU', 'Russian'),
      ('uk-UA', 'Ukrainian'),
      ('es-ES', 'Spanish'),
      ('fr-FR', 'French'),
      ('de-DE', 'German'),
      ('it-IT', 'Italian'),
      ('pt-BR', 'Portuguese (Brazil)'),
      ('zh-CN', 'Chinese (Simplified)'),
      ('ja-JP', 'Japanese'),
      ('ko-KR', 'Korean'),
      ('ar-SA', 'Arabic'),
      ('hi-IN', 'Hindi'),
      ('tr-TR', 'Turkish'),
      ('pl-PL', 'Polish'),
      ('nl-NL', 'Dutch'),
      ('sv-SE', 'Swedish'),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.8,
          minChildSize: 0.3,
          expand: false,
          builder: (ctx, scrollController) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Select Language',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: languages.length,
                    itemBuilder: (ctx, index) {
                      final (code, name) = languages[index];

                      final isSelected = current == code;

                      return ListTile(
                        leading: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: isSelected ? AppTheme.kPrimary : null,
                        ),
                        title: Text(name),
                        subtitle: Text(
                          code,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () {
                          unawaited(notifier.updateLanguage(code));

                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showVoicePicker(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(ttsManagerProvider.notifier);

    final current = ref.read(ttsManagerProvider).voice;

    final voices = await notifier.getVoices();

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _VoicePickerSheet(
          voices: voices,
          current: current,
          notifier: notifier,
        );
      },
    );
  }
}

class _VoicePickerSheet extends StatefulWidget {
  final List<TtsEngineVoice> voices;
  final String current;
  final TtsManager notifier;

  const _VoicePickerSheet({
    required this.voices,
    required this.current,
    required this.notifier,
  });

  @override
  State<_VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<_VoicePickerSheet> {
  final TextEditingController _searchController = TextEditingController();

  final EdgeTtsEngine _engine = EdgeTtsEngine();

  final TtsPlayer _samplePlayer = TtsPlayer();

  String _query = '';
  String? _playingVoiceId;
  late String _selectedVoice;

  int _sampleGeneration = 0;
  bool _sampleBusy = false;

  @override
  void initState() {
    super.initState();

    _selectedVoice = widget.current;
  }

  @override
  void dispose() {
    ++_sampleGeneration;

    _searchController.dispose();

    unawaited(_samplePlayer.dispose());

    unawaited(_engine.close());

    super.dispose();
  }

  Future<void> _stopSample() async {
    ++_sampleGeneration;

    try {
      await _samplePlayer.stop();
    } catch (e) {
      Log.w('VoiceSample', 'Failed to stop sample: $e');
    }

    if (!mounted) return;

    setState(() {
      _playingVoiceId = null;
      _sampleBusy = false;
    });
  }

  Future<void> _playSample(TtsEngineVoice voice) async {
    if (_sampleBusy && _playingVoiceId == voice.id) {
      await _stopSample();
      return;
    }

    final generation = ++_sampleGeneration;

    try {
      await _samplePlayer.stop();
    } catch (e) {
      Log.w('VoiceSample', 'Failed to stop previous sample: $e');
    }

    if (!mounted || generation != _sampleGeneration) {
      return;
    }

    setState(() {
      _playingVoiceId = voice.id;
      _sampleBusy = true;
    });

    try {
      final audio = BytesBuilder();

      await for (final event in _engine.synthesize(
        'Hello! This is a sample of the '
        '${voice.name} voice. '
        'You can use this voice for '
        'reading novels.',
        voiceId: voice.id,
        locale: voice.locale,
        rate: '+0%',
        pitch: '+0Hz',
      )) {
        if (!mounted || generation != _sampleGeneration) {
          return;
        }

        switch (event) {
          case TtsAudioBytes():
            if (event.bytes.isNotEmpty) {
              audio.add(event.bytes);
            }

          case TtsSynthesisError():
            throw event.error;

          case TtsWordBoundary():
          case TtsTurnEnd():
            break;
        }
      }

      if (!mounted || generation != _sampleGeneration) {
        return;
      }

      final bytes = audio.takeBytes();

      if (bytes.isEmpty) {
        throw StateError('Voice sample returned no audio');
      }

      final source = TtsStreamSource.fromBytes(bytes);

      await _samplePlayer.setPlaylist([source]);

      if (!mounted || generation != _sampleGeneration) {
        await _samplePlayer.stop();
        return;
      }

      await _samplePlayer.play();

      if (!mounted || generation != _sampleGeneration) {
        await _samplePlayer.stop();
        return;
      }

      // Wait until the source naturally finishes. This keeps the play icon
      // active for the duration of the preview.
      while (mounted &&
          generation == _sampleGeneration &&
          _samplePlayer.audioPlayer.playing) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      if (mounted && generation == _sampleGeneration) {
        Log.e('VoiceSample', 'Sample synthesis failed', e);
      }
    } finally {
      if (generation == _sampleGeneration) {
        try {
          await _samplePlayer.stop();
        } catch (_) {}

        if (mounted) {
          setState(() {
            _playingVoiceId = null;
            _sampleBusy = false;
          });
        }
      }
    }
  }

  List<TtsEngineVoice> get _filtered {
    final query = _query.trim().toLowerCase();

    if (query.isEmpty) {
      return widget.voices;
    }

    return widget.voices
        .where(
          (voice) =>
              voice.name.toLowerCase().contains(query) ||
              voice.locale.toLowerCase().contains(query) ||
              voice.id.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Select Voice',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

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
                          onPressed: () {
                            _searchController.clear();

                            setState(() {
                              _query = '';
                            });
                          },
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                },
              ),
            ),

            const SizedBox(height: 4),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${filtered.length} voices',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            ListTile(
              dense: true,
              leading: Icon(
                _selectedVoice.isEmpty
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: _selectedVoice.isEmpty ? AppTheme.kPrimary : null,
              ),
              title: const Text('Default (Brian)'),
              onTap: () {
                unawaited(widget.notifier.updateVoice(''));

                setState(() {
                  _selectedVoice = '';
                });

                Navigator.pop(ctx);
              },
            ),

            const Divider(height: 1),

            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No voices match your search.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (ctx, index) {
                        final voice = filtered[index];

                        final isSelected = _selectedVoice == voice.id;

                        final isPlaying = _playingVoiceId == voice.id;

                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: isSelected ? AppTheme.kPrimary : null,
                          ),
                          title: Text(
                            voice.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              voice.locale,
                              if (voice.gender != null &&
                                  voice.gender!.isNotEmpty)
                                voice.gender!,
                            ].join(' · '),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              isPlaying
                                  ? Icons.stop_circle
                                  : Icons.play_circle_outline,
                              color: isPlaying
                                  ? AppTheme.kPrimary
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            tooltip: isPlaying ? 'Stop sample' : 'Play sample',
                            onPressed: _sampleBusy && !isPlaying
                                ? null
                                : () => _playSample(voice),
                          ),
                          onTap: () {
                            unawaited(widget.notifier.updateVoice(voice.id));

                            setState(() {
                              _selectedVoice = voice.id;
                            });

                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
