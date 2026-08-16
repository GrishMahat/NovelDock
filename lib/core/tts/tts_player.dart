import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'tts_stream_source.dart';

/// Thin wrapper around one [AudioPlayer] per TTS session.
///
/// The player plays a playlist where every TTS chunk is its own
/// [TtsStreamSource]. mpv therefore sees a real playlist: each chunk is a
/// discrete media entry with a clean EOF, and loop-all maps to native mpv
/// playlist looping. Chunks are appended to the playlist as they are
/// synthesized. No temp files are used anywhere.
class TtsPlayer {
  final AudioPlayer _player = AudioPlayer();
  final List<TtsStreamSource> _sources = [];

  AudioPlayer get audioPlayer => _player;

  /// Number of items currently loaded in the playlist.
  int get playlistLength => _player.audioSources.length;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  /// Replaces the current playlist with [sources] (usually the first chunk).
  /// Awaiting this waits for the first item's audio to load.
  Future<void> setPlaylist(List<AudioSource> sources) async {
    await _closePlaylist();
    for (final s in sources) {
      if (s is TtsStreamSource) _sources.add(s);
    }
    await _player.setAudioSources(sources);
  }

  /// Appends a newly synthesized chunk to the active playlist.
  Future<void> addToPlaylist(AudioSource source) async {
    if (source is TtsStreamSource) _sources.add(source);
    await _player.addAudioSource(source);
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);

  Future<void> stop() async {
    await _player.stop();
    await _closePlaylist();
  }

  /// Closes every chunk stream owned by the current playlist so the proxy
  /// responses end cleanly and no stream controller outlives its chunk.
  Future<void> _closePlaylist() async {
    for (final source in _sources) {
      if (!source.isClosed) {
        await source.closeStream();
      }
    }
    _sources.clear();
    await _player.clearAudioSources();
  }

  Future<void> dispose() async {
    await _closePlaylist();
    await _player.dispose();
  }
}
