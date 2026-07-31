import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'tts_stream_source.dart';

/// Thin wrapper around one [AudioPlayer] per TTS session.
///
/// The player plays from a [TtsStreamSource]; there is exactly one player for
/// the whole session, and no temp files anywhere.
class TtsPlayer {
  final AudioPlayer _player = AudioPlayer();
  TtsStreamSource? _source;

  AudioPlayer get audioPlayer => _player;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  Future<void> setSource(TtsStreamSource source) async {
    await _closeSource();
    _source = source;
    await _player.setAudioSource(source);
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> stop() async {
    await _player.stop();
    await _closeSource();
  }

  Future<void> _closeSource() async {
    final source = _source;
    _source = null;
    if (source != null) {
      await source.closeStream();
    }
  }

  Future<void> dispose() async {
    await _closeSource();
    await _player.dispose();
  }
}
