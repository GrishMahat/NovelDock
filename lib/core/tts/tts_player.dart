import 'package:just_audio/just_audio.dart';

/// Thin wrapper around one [AudioPlayer] per TTS session.
///
/// Each synthesized TTS chunk is represented by its own complete
/// [TtsStreamSource]. The player therefore sees a normal playlist where every
/// chunk has a clean EOF.
///
/// No temporary files are required.
class TtsPlayer {
  final AudioPlayer _player = AudioPlayer();

  bool _disposed = false;

  AudioPlayer get audioPlayer => _player;

  /// Number of items currently loaded in the playlist.
  int get playlistLength => _player.audioSources.length;

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  /// Replaces the current playlist with [sources].
  ///
  /// The player owns the playlist after this call. TTS sources are immutable
  /// complete byte streams, so there is no producer/controller lifecycle to
  /// close here.
  Future<void> setPlaylist(List<AudioSource> sources) async {
    if (_disposed) return;

    final snapshot = List<AudioSource>.unmodifiable(sources);

    await _player.setAudioSources(snapshot, preload: true);
  }

  /// Appends a newly synthesized chunk.
  Future<void> addToPlaylist(AudioSource source) async {
    if (_disposed) return;

    await _player.addAudioSource(source);
  }

  Future<void> play() async {
    if (_disposed) return;

    await _player.play();
  }

  Future<void> pause() async {
    if (_disposed) return;

    await _player.pause();
  }

  Future<void> setSpeed(double speed) async {
    if (_disposed || speed <= 0) return;

    await _player.setSpeed(speed);
  }

  Future<void> setLoopMode(LoopMode mode) async {
    if (_disposed) return;

    await _player.setLoopMode(mode);
  }

  /// Stops playback and clears the active playlist.
  Future<void> stop() async {
    if (_disposed) return;

    try {
      await _player.stop();
    } finally {
      // clearAudioSources() can fail if the player is already being torn
      // down. The playlist itself is no longer useful after stop anyway.
      try {
        await _player.clearAudioSources();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;

    try {
      await _player.stop();
    } catch (_) {}

    try {
      await _player.clearAudioSources();
    } catch (_) {}

    await _player.dispose();
  }
}
