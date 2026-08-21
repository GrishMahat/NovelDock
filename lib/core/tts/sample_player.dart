import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'engine/edge_tts_engine.dart';
import 'engine/tts_engine.dart';
import 'tts_player.dart';
import 'tts_stream_source.dart';

/// Plays short voice previews for the settings voice picker.
///
/// Deep module behind a 3-method interface: engine creation, the
/// synthesize → accumulate → stream → play loop, cancellation, and natural
/// completion detection all live here. It owns its own engine and player so
/// a sample never disturbs an active TTS session.
class TtsSamplePlayer {
  TtsSamplePlayer({TtsEngine? engine}) : _engine = engine ?? EdgeTtsEngine();

  final TtsEngine _engine;
  final TtsPlayer _player = TtsPlayer();

  bool _playing = false;
  bool _disposed = false;
  int _generation = 0;

  /// True while a sample is playing or being synthesized.
  bool get isPlaying => _playing;

  /// Synthesizes and plays a short sample of [voice].
  ///
  /// Interrupts any currently playing sample first. Completes when the sample
  /// finishes naturally, or early when [stop] or a newer [playSample] cancels
  /// it.
  Future<void> playSample(TtsEngineVoice voice) async {
    if (_disposed) return;

    final generation = ++_generation;
    _playing = false;

    try {
      await _player.stop();
    } catch (_) {}

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
        if (generation != _generation) return;

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

      if (generation != _generation) return;

      final bytes = audio.takeBytes();

      if (bytes.isEmpty) {
        throw StateError('Voice sample returned no audio');
      }

      final source = TtsStreamSource.fromBytes(bytes);

      await _player.setPlaylist([source]);

      if (generation != _generation) {
        await _player.stop();
        return;
      }

      await _player.play();

      if (generation != _generation) {
        await _player.stop();
        return;
      }

      _playing = true;

      // Keep the play state active until the sample ends on its own.
      await _player.processingStateStream.firstWhere(
        (s) => s == ProcessingState.completed || s == ProcessingState.idle,
      );
    } finally {
      if (generation == _generation) {
        _playing = false;

        try {
          await _player.stop();
        } catch (_) {}
      }
    }
  }

  /// Cancels any in-flight sample and stops playback.
  Future<void> stop() async {
    ++_generation;
    _playing = false;

    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    ++_generation;
    _playing = false;

    await _player.dispose();
  }
}
