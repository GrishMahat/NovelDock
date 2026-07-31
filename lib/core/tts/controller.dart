import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'engine/tts_engine.dart';
import 'chunker.dart';
import 'tts_player.dart';
import 'tts_stream_source.dart';
import '../utils/logger.dart';

const _tag = 'TtsController';

/// Drives TTS playback: synthesizes chunks through a [TtsEngine] into one
/// continuous [TtsStreamSource], tracks word boundaries from player position,
/// and handles prefetch, stalls, and skips.
///
/// Audio bytes are appended to the stream source as they arrive (first-bytes
/// latency), in chunk order. Word highlighting and chunk completion are
/// event-driven off the player's position stream: `position -
/// cumulativeEnd(chunk)` selects the current word from that chunk's boundary
/// table, and crossing a chunk's end advances the playhead.
class TtsPlaybackController {
  /// How many chunks ahead of the playhead may be synthesized.
  final int prefetchWindow;

  /// Dropout threshold before a stall recovery is triggered.
  final Duration stallTimeout;

  final TtsPlayer _player = TtsPlayer();
  TtsEngine? _engine;
  late final StreamSubscription<Duration> _positionSub;

  List<TtsChunk> _chunks = const [];
  final List<List<TtsWordBoundary>?> _boundaries = [];
  final List<Duration> _cumulativeEnds = [];

  int _playhead = 0;
  int _startedChunk = -1;
  int _lastWordIndex = -1;
  bool _cancelled = true;
  bool _stopped = true;
  bool _completed = false;
  int _generation = 0;
  DateTime _lastBytesAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPositionAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _paused = false;
  Timer? _stallTimer;

  String _voiceId = '';
  String _rate = '+0%';
  String _pitch = '+0Hz';
  String? _locale;

  /// Raised when the chunk's audio starts playing (speech-aligned).
  void Function(int chunkIndex)? onChunkStart;

  /// Raised when the highlighted word changes.
  void Function(int chunkIndex, int wordIndexInChunk)? onWord;

  /// Raised when a chunk has finished playing.
  void Function(int chunkIndex)? onChunkCompleted;

  /// Raised when the whole session finished playing.
  void Function()? onCompleted;

  /// Raised on synthesis or stall failures (recovered or fatal).
  void Function(Object error, {required bool fatal})? onError;

  TtsPlaybackController({
    this.prefetchWindow = 4,
    this.stallTimeout = const Duration(seconds: 4),
  }) {
    _positionSub = _player.positionStream.listen(_onPosition);
    _player.processingStateStream.listen(_onPlayerState);
  }

  TtsPlayer get player => _player;
  List<TtsChunk> get chunks => _chunks;
  int get currentChunkIndex => _playhead.clamp(0, _chunks.length - 1);
  bool get isRunning => !_cancelled && !_completed && !_stopped;
  Duration get position => _player.audioPlayer.position;

  Duration get totalDuration {
    var total = Duration.zero;
    for (final chunk in _chunks) {
      total += Duration(milliseconds: chunk.estimatedDurationMs);
    }
    return total;
  }

  /// Starts a new session from [startIndex]. Any running session is stopped.
  Future<void> start({
    required List<TtsChunk> chunks,
    required TtsEngine engine,
    required String voiceId,
    required String rate,
    required String pitch,
    String? locale,
    int startIndex = 0,
    double speed = 1.0,
  }) async {
    await stop();
    _engine = engine;
    engine.reopen();
    _chunks = chunks;
    _voiceId = voiceId;
    _rate = rate;
    _pitch = pitch;
    _locale = locale;
    _completed = false;
    _paused = false;
    _playhead = startIndex.clamp(0, chunks.length - 1);
    _startedChunk = -1;
    _lastWordIndex = -1;
    _resetChunkState();
    _startStallTimer();
    await _startPipeline(_playhead);
  }

  Future<void> pause() async {
    if (_stopped || _completed) return;
    _paused = true;
    await _player.pause();
  }

  Future<void> resume() async {
    if (_stopped || _completed) return;
    _paused = false;
    await _player.play();
  }

  Future<void> stop() async {
    _generation++;
    _cancelled = true;
    _stopped = true;
    _stallTimer?.cancel();
    await _player.stop();
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      await engine.close();
    }
  }

  /// Restarts the current chunk from its beginning.
  Future<void> restartCurrent() => _restartAt(_playhead);

  /// Skips to [chunkIndex], restarting the pipeline there.
  Future<void> skipTo(int chunkIndex) {
    if (chunkIndex < 0 || chunkIndex >= _chunks.length) {
      return Future<void>.value();
    }
    return _restartAt(chunkIndex);
  }

  Future<void> skipForward() => skipTo(_playhead + 1);

  /// Seeks to the chunk containing [position] (stream sources are not
  /// seekable within a chunk; the pipeline restarts at the target chunk).
  Future<void> seekTo(Duration position) {
    if (_chunks.isEmpty || _cancelled || _completed || _stopped) {
      return Future<void>.value();
    }
    var target = _chunks.length - 1;
    Duration? acc;
    for (var i = 0; i < _chunks.length; i++) {
      final end = _cumulativeEnds[i] > Duration.zero
          ? _cumulativeEnds[i]
          : (acc ?? Duration.zero) +
              Duration(milliseconds: _chunks[i].estimatedDurationMs);
      if (position < end) {
        target = i;
        break;
      }
      acc = end;
    }
    return skipTo(target);
  }

  Future<void> setRate(String rate) async {
    _rate = rate;
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  /// Applies to chunks synthesized from now on.
  Future<void> setPitch(String pitch) async {
    _pitch = pitch;
  }

  /// Starts the audio pipeline (synthesis -> stream source -> player) from
  /// [fromIndex] with a fresh stream source.
  Future<void> _startPipeline(int fromIndex) async {
    final generation = ++_generation;
    _cancelled = false;
    _stopped = false;
    _startedChunk = -1;
    _lastWordIndex = -1;
    await _player.stop();
    final source = TtsStreamSource();
    _lastBytesAt = DateTime.now();
    _lastPositionAt = DateTime.now();
    // Feed bytes before awaiting the load: for an unknown-length stream the
    // player only becomes ready once the first bytes arrive, so waiting for
    // setSource first would deadlock (mpv buffers forever, playLoop never
    // runs). Bytes added before the player connects are buffered by the
    // stream controller.
    unawaited(_playLoop(fromIndex, generation, source));
    try {
      await _player.setSource(source);
      await _player.play();
    } on PlayerInterruptedException {
      // Superseded by stop()/skipTo() while loading; the newer pipeline owns
      // the player now.
    }
  }

  Future<void> _playLoop(
    int fromIndex,
    int generation,
    TtsStreamSource source,
  ) async {
    final engine = _engine;
    if (engine == null) return;
    try {
      for (var i = fromIndex; i < _chunks.length; i++) {
        if (_cancelled || generation != _generation) return;

        // Bound the look-ahead to the prefetch window.
        while (i - _playhead >= prefetchWindow && !_cancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (_cancelled || generation != _generation) return;

        final chunk = _chunks[i];
        final boundaries = <TtsWordBoundary>[];
        var ok = false;
        await for (final event in engine.synthesize(
          chunk.text,
          voiceId: _voiceId,
          rate: _rate,
          pitch: _pitch,
          locale: _locale,
        )) {
          if (_cancelled || generation != _generation) return;
          switch (event) {
            case TtsAudioBytes():
              if (!source.isClosed) {
                source.addBytes(event.bytes);
              }
              _lastBytesAt = DateTime.now();
            case TtsWordBoundary():
              boundaries.add(event);
            case TtsTurnEnd():
              ok = true;
            case TtsSynthesisError():
              if (event.fatal) {
                throw event.error;
              }
          }
        }
        if (_cancelled || generation != _generation) return;
        if (!ok) {
          throw StateError('Turn ended without audio for chunk $i');
        }
        if (i >= _boundaries.length) return;
        _boundaries[i] = boundaries;
        final chunkEnd = boundaries.isEmpty
            ? Duration(milliseconds: chunk.estimatedDurationMs)
            : boundaries.last.offset + boundaries.last.duration;
        // Store absolute ends: cumulativeEnds[i] = start of chunk 0 audio +
        // this chunk's end. Position events are absolute within the stream.
        final absoluteEnd = i > 0 && _cumulativeEnds[i - 1] > Duration.zero
            ? _cumulativeEnds[i - 1] + chunkEnd
            : chunkEnd;
        _cumulativeEnds[i] = absoluteEnd;
        for (var j = i + 1; j < _chunks.length; j++) {
          _cumulativeEnds[j] = absoluteEnd;
        }
      }
      // All chunks synthesized. Close the source so the player receives a
      // clean EOF with every buffered byte flushed: with unknown-length HTTP
      // streams, mpv treats an idle socket as EOF, which would truncate the
      // tail of the audio. Playback then runs on the fully-buffered audio.
      if (!source.isClosed) {
        await source.closeStream();
      }
    } on Object catch (e) {
      if (!_cancelled && generation == _generation) {
        Log.e(_tag, 'Pipeline failed: $e');
        onError?.call(e, fatal: true);
      }
    }
  }

  /// Reconnects and re-synthesizes from [fromIndex] with a fresh stream.
  Future<void> _restartAt(int fromIndex) async {
    ++_generation;
    _cancelled = true;
    _stallTimer?.cancel();
    final engine = _engine;
    if (engine != null) {
      await engine.close();
    }
    _playhead = fromIndex;
    _startedChunk = -1;
    _lastWordIndex = -1;
    _resetChunkState();
    _startStallTimer();
    await _startPipeline(fromIndex);
  }

  void _resetChunkState() {
    _boundaries
      ..clear()
      ..addAll(List<List<TtsWordBoundary>?>.filled(_chunks.length, null));
    _cumulativeEnds
      ..clear()
      ..addAll(List<Duration>.filled(_chunks.length, Duration.zero));
  }

  void _startStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_cancelled || _stopped || _completed || _paused) return;
      final now = DateTime.now();
      // A stall is no new bytes *and* no playback progress: prefetching means
      // bytes legitimately stop while audio is still playing out.
      final noBytes = now.difference(_lastBytesAt) > stallTimeout;
      final noProgress = now.difference(_lastPositionAt) > stallTimeout;
      if (noBytes && noProgress) {
        Log.w(_tag, 'Stall detected, restarting chunk $_playhead');
        onError?.call(StateError('Synthesis stalled'), fatal: false);
        unawaited(_restartAt(_playhead));
      }
    });
  }

  /// Completes the session when the player reports the stream is done.
  ///
  /// The reported position can land a hair below the boundary-derived end
  /// (rounding of the final MP3 frames), so the player's `completed` state is
  /// the authoritative "all audio played" signal.
  void _onPlayerState(ProcessingState state) {
    if (state != ProcessingState.completed) return;
    if (_cancelled || _stopped || _completed) return;
    _onPosition(Duration(days: 1));
  }

  /// Handles position events: word highlighting, chunk start/completion.
  void _onPosition(Duration position) {
    if (_cancelled || _stopped || _completed) return;
    _lastPositionAt = DateTime.now();
    if (_playhead >= _chunks.length) return;

    // Chunk start: first position past zero in a fresh pipeline.
    if (_startedChunk != _playhead) {
      _startedChunk = _playhead;
      onChunkStart?.call(_playhead);
    }

    final before = _playhead > 0 ? _cumulativeEnds[_playhead - 1] : Duration.zero;
    final elapsed = position - before;
    final boundaries = _playhead < _boundaries.length
        ? _boundaries[_playhead]
        : null;

    if (boundaries != null && boundaries.isNotEmpty && !elapsed.isNegative) {
      var wordIndex = -1;
      for (var wi = boundaries.length - 1; wi >= 0; wi--) {
        if (elapsed >= boundaries[wi].offset) {
          wordIndex = wi;
          break;
        }
      }
      if (wordIndex != -1 && wordIndex != _lastWordIndex) {
        _lastWordIndex = wordIndex;
        onWord?.call(_playhead, wordIndex);
      }
    }

    // Chunk completion: playhead's end recorded and crossed.
    while (_playhead < _chunks.length &&
        _cumulativeEnds[_playhead] > Duration.zero &&
        position >= _cumulativeEnds[_playhead]) {
      onChunkCompleted?.call(_playhead);
      _playhead++;
      _lastWordIndex = -1;
      if (_playhead < _chunks.length) {
        onChunkStart?.call(_playhead);
        _startedChunk = _playhead;
      }
    }

    if (_playhead >= _chunks.length && !_completed) {
      _completed = true;
      _stallTimer?.cancel();
      unawaited(_player.stop());
      onCompleted?.call();
    }
  }

  void dispose() {
    unawaited(stop());
    _positionSub.cancel();
  }
}
