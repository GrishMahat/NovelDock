import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/logger.dart';
import 'tts_engine.dart';

const _tag = 'SystemTts';

/// On-device platform TTS engine (Android system TextToSpeech).
///
/// The platform engine cannot stream audio bytes while speaking, so this
/// implementation synthesizes each turn to a temporary WAV file
/// ([FlutterTts.synthesizeToFile] with a full path) and emits the bytes as
/// one [TtsAudioBytes] event. Word boundaries are unavailable.
class SystemTtsEngine extends TtsEngine {
  /// Whether the underlying platform plugin can run here.
  static bool get isSupported => Platform.isAndroid;

  FlutterTts? _tts;

  @override
  String get id => 'system';

  @override
  String get displayName => 'Device voice';

  @override
  bool get supportsWordBoundaries => false;

  @override
  bool get requiresNetwork => false;

  Future<FlutterTts> _ensure() async {
    if (_tts != null) return _tts!;
    final tts = FlutterTts();
    // Makes synthesizeToFile() resolve only after the file is fully written.
    await tts.awaitSynthCompletion(true);
    _tts = tts;
    return tts;
  }

  @override
  Future<void> init() async {
    if (!isSupported) {
      throw UnsupportedError('System TTS is not supported on this platform');
    }
    await _ensure();
  }

  @override
  Future<List<TtsEngineVoice>> getVoices() async {
    if (!isSupported) return const [];
    try {
      final tts = await _ensure();
      final raw = await tts.getVoices;
      if (raw is! List) return const [];
      final voices = <TtsEngineVoice>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final name = entry['name']?.toString() ?? '';
        final locale = entry['locale']?.toString() ?? '';
        if (name.isEmpty || locale.isEmpty) continue;
        voices.add(TtsEngineVoice(id: name, name: name, locale: locale));
      }
      Log.i(_tag, 'Discovered ${voices.length} system voices');
      return voices;
    } catch (e) {
      Log.e(_tag, 'getVoices failed: $e');
      return const [];
    }
  }

  @override
  Future<void> close() async {
    final tts = _tts;
    _tts = null;
    if (tts == null) return;
    try {
      await tts.stop();
      await tts.setEngine('');
    } catch (_) {}
  }

  @override
  void reopen() {}

  /// Maps an Edge-style rate string (`+10%`) to a speech-rate multiplier
  /// where 1.0 is the platform default.
  double _rateFrom(String rate) {
    final match = RegExp(r'([+-]?\d+(?:\.\d+)?)\s*%').firstMatch(rate);
    final pct = match == null ? 0.0 : double.parse(match.group(1)!);
    return (1.0 + pct / 100).clamp(0.25, 4.0);
  }

  /// Maps an Edge-style pitch string (`+10Hz`, or a `%` value from legacy
  /// callers) to the platform pitch scale (0.5 to 2.0, default 1.0).
  double _pitchFrom(String pitch) {
    final hzMatch = RegExp(r'([+-]?\d+(?:\.\d+)?)\s*Hz').firstMatch(pitch);
    if (hzMatch != null) {
      return (1.0 + double.parse(hzMatch.group(1)!) / 200).clamp(0.5, 2.0);
    }
    final pctMatch = RegExp(r'([+-]?\d+(?:\.\d+)?)\s*%').firstMatch(pitch);
    final pct = pctMatch == null ? 0.0 : double.parse(pctMatch.group(1)!);
    return (1.0 + pct / 100).clamp(0.5, 2.0);
  }

  @override
  Stream<TtsSynthesisEvent> synthesize(
    String text, {
    required String voiceId,
    required String rate,
    required String pitch,
    String? locale,
  }) async* {
    try {
      final tts = await _ensure();

      var voiceSet = false;
      if (voiceId.isNotEmpty && locale != null && locale.isNotEmpty) {
        voiceSet =
            await tts.setVoice({'name': voiceId, 'locale': locale}) == 1;
      }
      if (!voiceSet && locale != null && locale.isNotEmpty) {
        await tts.setLanguage(locale);
      }
      await tts.setSpeechRate(_rateFrom(rate));
      await tts.setPitch(_pitchFrom(pitch));

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/noveldock_tts_${DateTime.now().microsecondsSinceEpoch}.wav',
      );

      final result = await tts.synthesizeToFile(text, file.path, true);
      if (result != 1) {
        throw Exception('System TTS rejected synthesis (code: $result)');
      }

      final bytes = await file.readAsBytes();
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}

      if (bytes.isEmpty) {
        throw Exception('System TTS produced an empty audio file');
      }

      yield TtsAudioBytes(bytes);
      yield const TtsTurnEnd();
    } catch (e) {
      yield TtsSynthesisError(e);
    }
  }
}
