import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'engine/tts_engine.dart';
import 'chunker.dart';
import 'tts_player.dart';
import 'tts_stream_source.dart';
import '../utils/logger.dart';

const _tag = 'TtsController';

/// Drives TTS playback: synthesizes chunks through a [TtsEngine] into a
/// The player plays a [setAudioSources] playlist (one complete
/// [TtsStreamSource] per
/// chunk), tracks word boundaries from the player's per-item position, and
/// handles prefetch, stalls, premature completion, and loop-all.
///
/// The first chunk is synthesized fully and loaded as the head of the
/// playlist; later chunks are appended as they are synthesized (bounded by
/// the prefetch window). mpv sees discrete playlist items, so each chunk ends
/// with a clean EOF and loop-all maps to native mpv playlist looping.
/// Word highlighting uses the per-item position: boundary offsets are relative
/// to their chunk, and chunk completion is driven by item changes.
class TtsPlaybackController {
  /// How many chunks ahead of the playhead may be synthesized.
  final int prefetchWindow;

  /// Dropout threshold before a stall recovery is triggered.
  final Duration stallTimeout;

  /// Consecutive stalls (or premature completions) at the same chunk before
  /// the controller gives up with a fatal error. Bounds stall recovery: a
  /// session that cannot advance a chunk after one warm and one cold restart
  /// is not going to heal on its own, and restarting forever just thrashes
  /// the Edge session.
  final int maxStallRestarts;

  final TtsPlayer _player = TtsPlayer();
  TtsEngine? _engine;
  late final StreamSubscription<Duration> _positionSub;

  List<TtsChunk> _chunks = const [];
  final List<List<TtsWordBoundary>?> _boundaries = [];
  final List<Duration> _cumulativeEnds = [];
  final List<Uint8List?> _audioCache = [];
  final List<List<TtsWordBoundary>?> _boundaryCache = [];

  int _pipelineFromIndex = 0;
  int _playhead = 0;
  int _startedChunk = -1;
  int _lastWordIndex = -1;
  bool _cancelled = true;
  bool _stopped = true;
  bool _completed = false;
  bool _prematurelyCompleted = false;
  bool _pipelineFailed = false;
  int _generation = 0;
  DateTime _lastBytesAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPositionAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _paused = false;
  bool _synthesizing = false;
  Timer? _stallTimer;
  int _stallCount = 0;
  int _stallAtChunk = -1;
  int _prematureCount = 0;
  int _prematureAtChunk = -1;

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
    this.maxStallRestarts = 3,
  }) {
    _positionSub = _player.positionStream.listen(_onPosition);
    _player.processingStateStream.listen(_onPlayerState);
  }

  TtsPlayer get player => _player;
  List<TtsChunk> get chunks => _chunks;
  int get currentChunkIndex => _playhead.clamp(0, _chunks.length - 1);
  bool get isRunning => !_cancelled && !_completed && !_stopped;
  Duration get position => _player.audioPlayer.position;

  /// Testing-only access to per-chunk word boundaries.
  @visibleForTesting
  List<List<TtsWordBoundary>?> get boundariesForTest =>
      List.unmodifiable(_boundaries);

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
    _stallCount = 0;
    _stallAtChunk = -1;
    _prematureCount = 0;
    _prematureAtChunk = -1;
    _pipelineFailed = false;
    _resetChunkState(clearAudioCache: true);
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

  /// Applies loop-all (or disables it) to the underlying playlist.
  ///
  /// With a per-chunk playlist, [LoopMode.all] maps to native mpv playlist
  /// looping: the chapter repeats chunk-by-chunk, and word highlighting wraps.
  Future<void> setLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
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

  /// Seeks to the chunk containing [position] (playlist items are not seekable
  /// within a chunk; the pipeline restarts at the target chunk).
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

  /// Starts the audio pipeline (synthesis -> per-chunk playlist -> player)
  /// from [fromIndex] with a fresh playlist.
  Future<void> _startPipeline(int fromIndex) async {
    final generation = ++_generation;
    _cancelled = false;
    _stopped = false;
    _startedChunk = -1;
    _lastWordIndex = -1;
    _prematurelyCompleted = false;
    _pipelineFailed = false;
    _pipelineFromIndex = fromIndex;
    await _player.stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (generation != _generation) return;
    _lastBytesAt = DateTime.now();
    _lastPositionAt = DateTime.now();
    _startStallTimer();
    // The first chunk must be fully synthesized before the player loads: mpv
    // only becomes ready once the first playlist item has complete bytes.
    try {
      await _loadFirstChunk(fromIndex, generation);
    } on PlayerInterruptedException {
      // Superseded by stop()/skipTo() while loading; the newer pipeline owns
      // the player now.
      return;
    } on Object catch (e) {
      if (!_cancelled && generation == _generation) {
        _pipelineFailed = true;
        Log.e(_tag, 'Pipeline failed to start: $e');
        onError?.call(e, fatal: true);
      }
      return;
    }
    if (generation != _generation) return;
    unawaited(_playRest(fromIndex + 1, generation));
  }

  /// Synthesizes the first chunk and loads it as the head of a fresh playlist.
  Future<void> _loadFirstChunk(int i, int generation) async {
    final bytes = await _synthesizeChunk(i, generation);
    if (bytes == null || generation != _generation || _cancelled) return;
    final source = TtsStreamSource(contentLength: bytes.length);
    source.addBytes(bytes);
    await source.closeStream();
    await _player.setPlaylist([source]);
    if (generation != _generation) {
      await _player.stop();
      return;
    }
    await _player.play();
  }

  /// Synthesizes the remaining chunks, appending each to the playlist once it
  /// is complete, bounded by the prefetch window.
  Future<void> _playRest(int from, int generation) async {
    try {
      for (var i = from; i < _chunks.length; i++) {
        if (_cancelled || generation != _generation) return;

        // Bound the look-ahead to the prefetch window.
        while (i - _playhead >= prefetchWindow && !_cancelled) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (_cancelled || generation != _generation) return;

        final bytes = await _synthesizeChunk(i, generation);
        if (bytes == null || generation != _generation || _cancelled) return;

        final source = TtsStreamSource(contentLength: bytes.length);
        source.addBytes(bytes);
        await source.closeStream();
        await _player.addToPlaylist(source);

        // If mpv hit the end of the loaded playlist while synthesis was in
        // flight, restart at the playhead now that the new chunk is ready. The
        // engine session is kept alive: recovery is just a fresh playlist,
        // and a cold reconnect here would starve the buffer and trigger the
        // next premature completion.
        if (_prematurelyCompleted &&
            !_cancelled &&
            generation == _generation) {
          Log.i(_tag,
              'Resuming playlist at chunk $_playhead after premature EOF');
          _prematurelyCompleted = false;
          unawaited(_restartAt(_playhead, keepEngine: true));
          return;
        }
      }
    } on Object catch (e) {
      _synthesizing = false;
      if (!_cancelled && generation == _generation) {
        _pipelineFailed = true;
        Log.e(_tag, 'Pipeline failed: $e');
        onError?.call(e, fatal: true);
      }
    }
  }

  /// Synthesizes chunk [i] (or replays it from the audio cache), returning its
  /// complete MP3 bytes. Returns `null` if the pipeline was superseded or
  /// cancelled mid-synthesis. Records the chunk's boundaries and cumulative
  /// end for seek/word tracking.
  Future<Uint8List?> _synthesizeChunk(int i, int generation) async {
    final cached = i < _audioCache.length ? _audioCache[i] : null;
    final boundaries = <TtsWordBoundary>[];
    if (cached != null) {
      if (i < _boundaryCache.length && _boundaryCache[i] != null) {
        boundaries.addAll(_boundaryCache[i]!);
      }
      _lastBytesAt = DateTime.now();
      _recordChunk(i, boundaries);
      return cached;
    }

    final engine = _engine;
    if (engine == null) {
      throw StateError('No TTS engine');
    }
    var ok = false;
    final builder = BytesBuilder();
    _synthesizing = true;
    try {
      await for (final event in engine.synthesize(
        _chunks[i].text,
        voiceId: _voiceId,
        rate: _rate,
        pitch: _pitch,
        locale: _locale,
      )) {
        if (_cancelled || generation != _generation) {
          _synthesizing = false;
          return null;
        }
        switch (event) {
          case TtsAudioBytes():
            builder.add(event.bytes);
            _lastBytesAt = DateTime.now();
          case TtsWordBoundary():
            boundaries.add(event);
          case TtsTurnEnd():
            ok = true;
          case TtsSynthesisError():
            if (event.fatal) {
              _synthesizing = false;
              throw event.error;
            }
        }
      }
    } finally {
      _synthesizing = false;
    }
    if (_cancelled || generation != _generation) return null;
    if (!ok) {
      throw StateError('Turn ended without audio for chunk $i');
    }
    final bytes = builder.takeBytes();
    if (i < _audioCache.length) {
      _audioCache[i] = bytes;
      _boundaryCache[i] = List.unmodifiable(boundaries);
    }
    _recordChunk(i, boundaries);
    return bytes;
  }

  /// Records chunk [i]'s boundaries and its absolute end within the current
  /// pipeline's timeline.
  void _recordChunk(int i, List<TtsWordBoundary> boundaries) {
    if (i >= _boundaries.length) return;
    _boundaries[i] = boundaries;
    final chunkEnd = boundaries.isEmpty
        ? Duration(milliseconds: _chunks[i].estimatedDurationMs)
        : boundaries.last.offset + boundaries.last.duration;
    final absoluteEnd =
        i > _pipelineFromIndex && _cumulativeEnds[i - 1] > Duration.zero
            ? _cumulativeEnds[i - 1] + chunkEnd
            : chunkEnd;
    _cumulativeEnds[i] = absoluteEnd;
  }

  /// Re-synthesizes from [fromIndex] with a fresh playlist.
  ///
  /// With [keepEngine] the engine/session is left untouched: premature-EOF
  /// recovery only needs a fresh playlist, and closing the engine there would
  /// force a cold reconnect whose gap starves the buffer and triggers the next
  /// premature completion (a self-perpetuating restart cascade). Without it
  /// the engine's session is invalidated (dropped) so the next turn reconnects
  /// fresh — used when a stall has wedged the session.
  Future<void> _restartAt(int fromIndex, {bool keepEngine = false}) async {
    ++_generation;
    _cancelled = true;
    _stallTimer?.cancel();
    if (!keepEngine) {
      _engine?.invalidateSession();
    }
    _playhead = fromIndex;
    _startedChunk = -1;
    _lastWordIndex = -1;
    _resetChunkState(clearAudioCache: false);
    _startStallTimer();
    await _startPipeline(fromIndex);
  }

  void _resetChunkState({bool clearAudioCache = false}) {
    _synthesizing = false;
    _boundaries
      ..clear()
      ..addAll(List<List<TtsWordBoundary>?>.filled(_chunks.length, null));
    _cumulativeEnds
      ..clear()
      ..addAll(List<Duration>.filled(_chunks.length, Duration.zero));
    if (clearAudioCache) {
      _audioCache
        ..clear()
        ..addAll(List<Uint8List?>.filled(_chunks.length, null));
      _boundaryCache
        ..clear()
        ..addAll(List<List<TtsWordBoundary>?>.filled(_chunks.length, null));
    }
  }

  void _startStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_cancelled || _stopped || _completed || _paused) return;
      // Only a stall when the player is actually playing: while loading
      // (cold edge-tts connection, synthesis in flight) both bytes and
      // position legitimately sit still, and restarting the pipeline there
      // would close the engine and loop cold reconnects.
      if (!_player.audioPlayer.playing) return;
      // A turn is still in flight: slow synthesis is not a stall. The engine
      // reports fatal errors on persistent network failures itself, and
      // restarting mid-turn only makes the gap longer.
      if (_synthesizing) return;
      final now = DateTime.now();
      // A stall is no new bytes *and* no playback progress: prefetching means
      // bytes legitimately stop while audio is still playing out.
      final noBytes = now.difference(_lastBytesAt) > stallTimeout;
      final noProgress = now.difference(_lastPositionAt) > stallTimeout;
      if (noBytes && noProgress) {
        // Count consecutive stalls at the same playhead. Real progress
        // (position events) resets the count in _onPosition.
        if (_stallAtChunk != _playhead) {
          _stallAtChunk = _playhead;
          _stallCount = 0;
        }
        _stallCount++;
        if (_stallCount >= maxStallRestarts) {
          // Bounded recovery: after a warm and a cold restart the chunk
          // still will not play — the session is wedged or the audio is
          // unplayable. Restarting further would just thrash the Edge
          // session in a death spiral.
          Log.e(_tag,
              'Giving up on chunk $_playhead after $_stallCount stalls');
          _stallTimer?.cancel();
          _pipelineFailed = true;
          onError?.call(
            StateError('Chunk $_playhead will not play '
                'after $_stallCount consecutive stalls'),
            fatal: true,
          );
          unawaited(stop());
          return;
        }
        Log.w(_tag,
            'Stall detected at chunk $_playhead (attempt $_stallCount)');
        onError?.call(StateError('Synthesis stalled'), fatal: false);
        // First stall at a chunk: the session is idle, so a warm restart
        // avoids a cold-reconnect gap. Repeated stalls at the same chunk
        // mean the session is suspect (wedged turn queue / dead socket):
        // invalidate it so the next turn forces a fresh connection.
        unawaited(_restartAt(_playhead, keepEngine: _stallCount == 1));
      }
    });
  }

  /// Completes the session when the player reports the playlist is done, or
  /// recovers (bounded) when mpv ran off the loaded items before all chunks
  /// were appended.
  ///
  /// With the per-chunk playlist, just_audio_media_kit only reports
  /// `completed` when the current index is the last loaded item and loop mode
  /// is off — so a completion while more chunks are pending is always
  /// premature.
  void _onPlayerState(ProcessingState state) {
    if (state != ProcessingState.completed) return;
    if (_cancelled || _stopped || _completed) return;

    if (_pipelineFailed) {
      unawaited(stop());
      return;
    }

    final loaded = _player.playlistLength;
    if (_playhead < _chunks.length && loaded < _chunks.length) {
      Log.w(_tag,
          'Player completed playlist at chunk $_playhead before all chunks '
          'loaded (loaded=$loaded/${_chunks.length}, synthesizing=$_synthesizing)');
      _prematurelyCompleted = true;
      if (!_synthesizing) {
        _handlePrematureCompletion();
      }
      return;
    }

    _finishSession();
  }

  /// Bounded recovery for premature completions: each premature completion at
  /// the same chunk counts toward [maxStallRestarts]; real forward progress
  /// (an item advance) resets the count in [_onPosition].
  void _handlePrematureCompletion() {
    if (_prematureAtChunk != _playhead) {
      _prematureAtChunk = _playhead;
      _prematureCount = 0;
    }
    _prematureCount++;
    if (_prematureCount >= maxStallRestarts) {
      Log.e(_tag,
          'Giving up on chunk $_playhead after $_prematureCount restarts');
      _stallTimer?.cancel();
      _pipelineFailed = true;
      onError?.call(
        StateError('Chunk $_playhead will not play '
            'after $_prematureCount consecutive restarts'),
        fatal: true,
      );
      unawaited(stop());
      return;
    }
    Log.w(_tag,
        'Premature completion at chunk $_playhead (attempt $_prematureCount)');
    onError?.call(StateError('Playback stalled'), fatal: false);
    // First premature completion: the session is idle, so a warm restart
    // avoids a cold-reconnect gap. Repeated completions at the same chunk mean
    // the session is suspect: invalidate it so the next turn reconnects fresh.
    unawaited(_restartAt(_playhead, keepEngine: _prematureCount == 1));
  }

  /// Handles position events: word highlighting and chunk start/completion.
  ///
  /// The player reports positions relative to the current playlist item, so
  /// the item index (relative to the pipeline start) selects the active chunk,
  /// and item changes drive chunk completion. Loop-all wraps the playlist, so
  /// a backward item index restarts the playhead.
  void _onPosition(Duration position) {
    if (_cancelled || _stopped || _completed) return;
    _lastPositionAt = DateTime.now();
    // Any position event means the player is making progress; a new chunk
    // (or a recovered stall) starts the stall count over.
    _stallCount = 0;
    _stallAtChunk = -1;
    if (_playhead >= _chunks.length) return;

    final itemIndex = _player.audioPlayer.currentIndex ?? 0;
    final chunk = (itemIndex + _pipelineFromIndex)
        .clamp(_pipelineFromIndex, _chunks.length - 1);

    if (chunk > _playhead) {
      // Advanced to a later item: every chunk in between played to the end.
      while (_playhead < chunk && _playhead < _chunks.length) {
        _fireTrailingWords(_playhead);
        onChunkCompleted?.call(_playhead);
        _playhead++;
        _lastWordIndex = -1;
      }
      // Real forward progress: a later chunk is now active, so any stalled
      // recovery counters are stale.
      _prematureCount = 0;
      _prematureAtChunk = -1;
    } else if (chunk < _playhead) {
      // LoopMode.all wrapped the playlist back to the first item.
      _playhead = chunk;
      _lastWordIndex = -1;
    }

    // Chunk start: first position event for the active chunk.
    if (_startedChunk != _playhead) {
      _startedChunk = _playhead;
      onChunkStart?.call(_playhead);
    }

    // Word highlighting from the per-item position: boundary offsets are
    // relative to their chunk.
    final boundaries = _playhead < _boundaries.length
        ? _boundaries[_playhead]
        : null;
    if (boundaries != null && boundaries.isNotEmpty && !position.isNegative) {
      var wordIndex = -1;
      for (var wi = boundaries.length - 1; wi >= 0; wi--) {
        if (position >= boundaries[wi].offset) {
          wordIndex = wi;
          break;
        }
      }
      if (wordIndex != -1 && wordIndex > _lastWordIndex) {
        for (var wi = _lastWordIndex + 1; wi <= wordIndex; wi++) {
          onWord?.call(_playhead, wi);
        }
        _lastWordIndex = wordIndex;
      }
    }
  }

  /// Fires the remaining word events for chunk [i] up to its last word.
  void _fireTrailingWords(int i) {
    final boundaries = i < _boundaries.length ? _boundaries[i] : null;
    if (boundaries == null || boundaries.isEmpty) return;
    for (var wi = _lastWordIndex + 1; wi < boundaries.length; wi++) {
      onWord?.call(i, wi);
    }
  }

  /// Completes the session: all chunks played, the playlist is done.
  void _finishSession() {
    if (_completed) return;
    _completed = true;
    _stallTimer?.cancel();
    while (_playhead < _chunks.length) {
      _fireTrailingWords(_playhead);
      onChunkCompleted?.call(_playhead);
      _playhead++;
      _lastWordIndex = -1;
    }
    unawaited(_player.stop());
    onCompleted?.call();
  }

  void dispose() {
    unawaited(stop());
    _positionSub.cancel();
  }
}
