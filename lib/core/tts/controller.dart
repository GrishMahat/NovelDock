import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'chunker.dart';
import 'engine/tts_engine.dart';
import 'tts_player.dart';
import 'tts_stream_source.dart';
import '../utils/logger.dart';

const _tag = 'TtsController';

/// Drives TTS playback:
///
/// synthesis -> complete per-chunk MP3 -> playlist -> player.
///
/// Each TTS chunk is its own [TtsStreamSource], so the player sees discrete
/// playlist entries with clean EOF boundaries.
class TtsPlaybackController {
  /// How many chunks ahead of the playhead may be synthesized.
  final int prefetchWindow;

  /// Dropout threshold before stall recovery.
  final Duration stallTimeout;

  /// Maximum consecutive recovery attempts at one chunk.
  final int maxStallRestarts;

  final TtsPlayer _player = TtsPlayer();

  TtsEngine? _engine;

  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<ProcessingState> _processingStateSub;

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
  bool _paused = false;
  bool _synthesizing = false;

  int _generation = 0;

  DateTime _lastBytesAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPositionAt = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _stallTimer;

  int _stallCount = 0;
  int _stallAtChunk = -1;

  int _prematureCount = 0;
  int _prematureAtChunk = -1;

  String _voiceId = '';
  String _rate = '+0%';
  String _pitch = '+0Hz';
  String? _locale;

  bool _disposed = false;

  /// Serializes high-level player mutations.
  Future<void> _operationQueue = Future<void>.value();

  /// Raised when a chunk actually starts playing.
  void Function(int chunkIndex)? onChunkStart;

  /// Raised when the highlighted word changes.
  void Function(int chunkIndex, int wordIndexInChunk)? onWord;

  /// Raised when a chunk finishes.
  void Function(int chunkIndex)? onChunkCompleted;

  /// Raised when the complete session finishes naturally.
  void Function()? onCompleted;

  /// Raised on synthesis/stall failures.
  void Function(Object error, {required bool fatal})? onError;

  TtsPlaybackController({
    this.prefetchWindow = 4,
    this.stallTimeout = const Duration(seconds: 4),
    this.maxStallRestarts = 3,
  }) : assert(prefetchWindow > 0),
       assert(stallTimeout > Duration.zero),
       assert(maxStallRestarts > 0) {
    _positionSub = _player.positionStream.listen(_onPosition);

    _processingStateSub = _player.processingStateStream.listen(_onPlayerState);
  }

  TtsPlayer get player => _player;

  List<TtsChunk> get chunks => _chunks;

  int get currentChunkIndex {
    if (_chunks.isEmpty) return 0;

    return _playhead.clamp(0, _chunks.length - 1);
  }

  bool get isRunning => !_cancelled && !_completed && !_stopped && !_disposed;

  Duration get position => _player.audioPlayer.position;

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

  /// Starts a completely new playback session.
  ///
  /// Any previous session is invalidated first.
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
    if (_disposed) return;

    final normalizedChunks = List<TtsChunk>.unmodifiable(chunks);

    if (normalizedChunks.isEmpty) {
      await stop();

      _chunks = const [];
      _resetChunkState(clearAudioCache: true);

      return;
    }

    final normalizedStart = startIndex.clamp(0, normalizedChunks.length - 1);

    final requestGeneration = ++_generation;

    await _enqueueOperation(() async {
      // A newer start/stop request already superseded this request while it
      // was waiting for the queue.
      if (_disposed || requestGeneration != _generation) {
        return;
      }

      await _stopInternal(invalidateEngine: false);

      // _stopInternal() bumps _generation itself. If a superseding stop()
      // bumped it again while we were stopping, this request is stale.
      if (_disposed || _generation != requestGeneration + 1) {
        return;
      }

      final pipelineGeneration = ++_generation;

      _engine = engine;
      engine.reopen();

      _chunks = normalizedChunks;
      _voiceId = voiceId;
      _rate = rate;
      _pitch = pitch;
      _locale = locale;

      _completed = false;
      _paused = false;
      _cancelled = false;
      _stopped = false;

      _playhead = normalizedStart;
      _startedChunk = -1;
      _lastWordIndex = -1;

      _stallCount = 0;
      _stallAtChunk = -1;
      _prematureCount = 0;
      _prematureAtChunk = -1;

      _pipelineFailed = false;

      _resetChunkState(clearAudioCache: true);

      await _startPipeline(normalizedStart, pipelineGeneration);
    });
  }

  Future<void> pause() async {
    if (_disposed || _stopped || _cancelled || _completed) {
      return;
    }

    _paused = true;
    _stallTimer?.cancel();
    _stallTimer = null;

    await _player.pause();
  }

  Future<void> resume() async {
    if (_disposed || _stopped || _cancelled || _completed) {
      return;
    }

    _paused = false;

    _lastPositionAt = DateTime.now();
    _lastBytesAt = DateTime.now();

    _startStallTimer();

    await _player.play();
  }

  Future<void> stop() async {
    if (_disposed) return;

    // Invalidate any start/restart currently waiting in the operation queue.
    ++_generation;

    await _enqueueOperation(() => _stopInternal(invalidateEngine: true));
  }

  Future<void> _stopInternal({required bool invalidateEngine}) async {
    ++_generation;

    _cancelled = true;
    _stopped = true;
    _paused = false;

    _prematurelyCompleted = false;
    _pipelineFailed = false;
    _synthesizing = false;

    _stallTimer?.cancel();
    _stallTimer = null;

    try {
      await _player.stop();
    } catch (e) {
      Log.w(_tag, 'Player stop failed: $e');
    }

    final engine = _engine;
    _engine = null;

    if (engine == null) return;

    if (invalidateEngine) {
      try {
        engine.invalidateSession();
      } catch (e) {
        Log.w(_tag, 'Engine invalidation failed: $e');
      }
    }

    try {
      await engine.close();
    } catch (e) {
      Log.w(_tag, 'Engine close failed: $e');
    }
  }

  Future<void> setLoopMode(LoopMode mode) async {
    if (_disposed) return;

    await _player.setLoopMode(mode);
  }

  Future<void> restartCurrent() {
    return _restartAt(_playhead);
  }

  Future<void> skipTo(int chunkIndex) {
    if (_chunks.isEmpty) {
      return Future<void>.value();
    }

    if (chunkIndex < 0 || chunkIndex >= _chunks.length) {
      return Future<void>.value();
    }

    return _restartAt(chunkIndex);
  }

  Future<void> skipForward() => skipTo(_playhead + 1);

  /// Seeks to the chunk whose estimated/known duration contains [position].
  ///
  /// This remains chunk-level seeking because individual playlist items are
  /// intentionally non-seekable.
  Future<void> seekTo(Duration position) async {
    if (_chunks.isEmpty || _cancelled || _completed || _stopped) {
      return;
    }

    final target = _findChunkForPosition(position);

    await skipTo(target);
  }

  int _findChunkForPosition(Duration position) {
    if (_chunks.isEmpty) return 0;

    var previousEnd = Duration.zero;

    for (var i = 0; i < _chunks.length; i++) {
      final knownEnd = i < _cumulativeEnds.length
          ? _cumulativeEnds[i]
          : Duration.zero;

      final estimatedEnd = knownEnd > previousEnd
          ? knownEnd
          : previousEnd +
                Duration(milliseconds: _chunks[i].estimatedDurationMs);

      if (position < estimatedEnd) {
        return i;
      }

      previousEnd = estimatedEnd;
    }

    return _chunks.length - 1;
  }

  Future<void> setRate(String rate) async {
    _rate = rate;
  }

  Future<void> setSpeed(double speed) async {
    if (_disposed || speed <= 0) {
      return;
    }

    await _player.setSpeed(speed);
  }

  Future<void> setPitch(String pitch) async {
    _pitch = pitch;
  }

  Future<void> _startPipeline(int fromIndex, int sessionGeneration) async {
    if (_disposed ||
        _chunks.isEmpty ||
        fromIndex < 0 ||
        fromIndex >= _chunks.length) {
      return;
    }

    if (!_isGenerationCurrent(sessionGeneration)) {
      return;
    }

    _cancelled = false;
    _stopped = false;

    _startedChunk = -1;
    _lastWordIndex = -1;

    _prematurelyCompleted = false;
    _pipelineFailed = false;

    _pipelineFromIndex = fromIndex;

    await _player.stop();

    if (!_isGenerationCurrent(sessionGeneration)) {
      return;
    }

    _lastBytesAt = DateTime.now();
    _lastPositionAt = DateTime.now();

    _startStallTimer();

    try {
      await _loadFirstChunk(fromIndex, sessionGeneration);
    } on PlayerInterruptedException {
      return;
    } on Object catch (e) {
      if (_isGenerationCurrent(sessionGeneration)) {
        _pipelineFailed = true;

        Log.e(_tag, 'Pipeline failed to start: $e');

        onError?.call(e, fatal: true);
      }

      return;
    }

    if (!_isGenerationCurrent(sessionGeneration)) {
      return;
    }

    unawaited(_playRest(fromIndex + 1, sessionGeneration));
  }

  Future<void> _loadFirstChunk(int index, int generation) async {
    final bytes = await _synthesizeChunk(index, generation);

    if (bytes == null || !_isGenerationCurrent(generation)) {
      return;
    }

    // TtsStreamSource is now immutable. The complete audio bytes are available
    // before the source is attached to just_audio.
    final source = TtsStreamSource.fromBytes(bytes);

    await _player.setPlaylist([source]);

    if (!_isGenerationCurrent(generation)) {
      await _player.stop();
      return;
    }

    await _player.play();
  }

  Future<void> _playRest(int from, int generation) async {
    try {
      for (var i = from; i < _chunks.length; i++) {
        if (!_isGenerationCurrent(generation)) {
          return;
        }

        while (i - _playhead >= prefetchWindow &&
            _isGenerationCurrent(generation)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        if (!_isGenerationCurrent(generation)) {
          return;
        }

        final bytes = await _synthesizeChunk(i, generation);

        if (bytes == null || !_isGenerationCurrent(generation)) {
          return;
        }

        final source = TtsStreamSource.fromBytes(bytes);

        await _player.addToPlaylist(source);

        if (!_isGenerationCurrent(generation)) {
          return;
        }

        // The player may have reached the end of the currently loaded
        // playlist while synthesis was still in progress. Resuming playback
        // directly (instead of a full restart) avoids re-playing cached
        // chunks and does not burn stall-restart attempts.
        if (_prematurelyCompleted && !_cancelled && generation == _generation) {
          _prematurelyCompleted = false;

          Log.i(
            _tag,
            'Resuming playlist at '
            'chunk $_playhead after '
            'premature EOF',
          );

          await _resumeAfterPrematureEof();
        }
      }
    } on Object catch (e) {
      _synthesizing = false;

      if (_isGenerationCurrent(generation)) {
        _pipelineFailed = true;

        Log.e(_tag, 'Pipeline failed: $e');

        onError?.call(e, fatal: true);
      }
    }
  }

  Future<void> _resumeAfterPrematureEof() async {
    if (_disposed || _cancelled || _stopped || _completed) {
      return;
    }

    try {
      // If the player completed the playlist, seek to the first item that
      // has not been played yet, then resume.
      await _player.audioPlayer.seekToNext();
    } catch (e) {
      Log.w(_tag, 'seekToNext after premature EOF failed: $e');
    }

    try {
      await _player.play();
    } catch (e) {
      Log.w(_tag, 'Resume after premature EOF failed: $e');
    }
  }

  Future<Uint8List?> _synthesizeChunk(int index, int generation) async {
    if (!_isGenerationCurrent(generation)) {
      return null;
    }

    if (index < 0 || index >= _chunks.length) {
      return null;
    }

    final cached = index < _audioCache.length ? _audioCache[index] : null;

    final boundaries = <TtsWordBoundary>[];

    if (cached != null) {
      if (index < _boundaryCache.length && _boundaryCache[index] != null) {
        boundaries.addAll(_boundaryCache[index]!);
      }

      _lastBytesAt = DateTime.now();

      _recordChunk(index, boundaries);

      return cached;
    }

    final engine = _engine;

    if (engine == null) {
      throw StateError('No TTS engine available');
    }

    final builder = BytesBuilder();

    _synthesizing = true;

    var completedNormally = false;

    try {
      await for (final event in engine.synthesize(
        _chunks[index].text,
        voiceId: _voiceId,
        rate: _rate,
        pitch: _pitch,
        locale: _locale,
      )) {
        if (!_isGenerationCurrent(generation)) {
          return null;
        }

        switch (event) {
          case TtsAudioBytes():
            if (event.bytes.isEmpty) {
              continue;
            }

            builder.add(event.bytes);
            _lastBytesAt = DateTime.now();

          case TtsWordBoundary():
            boundaries.add(event);

          case TtsTurnEnd():
            completedNormally = true;

          case TtsSynthesisError():
            throw event.error;
        }
      }
    } finally {
      _synthesizing = false;
    }

    if (!_isGenerationCurrent(generation)) {
      return null;
    }

    if (!completedNormally) {
      throw StateError(
        'Turn ended without completion '
        'for chunk $index',
      );
    }

    final bytes = builder.takeBytes();

    if (bytes.isEmpty) {
      throw StateError(
        'TTS produced no audio for '
        'chunk $index',
      );
    }

    if (index < _audioCache.length) {
      _audioCache[index] = bytes;

      _boundaryCache[index] = List.unmodifiable(boundaries);
    }

    _recordChunk(index, boundaries);

    return bytes;
  }

  void _recordChunk(int index, List<TtsWordBoundary> boundaries) {
    if (index < 0 || index >= _chunks.length || index >= _boundaries.length) {
      return;
    }

    _boundaries[index] = List.unmodifiable(boundaries);

    final chunkDuration = boundaries.isEmpty
        ? Duration(milliseconds: _chunks[index].estimatedDurationMs)
        : boundaries.last.offset + boundaries.last.duration;

    final previousEnd =
        index > _pipelineFromIndex && index - 1 < _cumulativeEnds.length
        ? _cumulativeEnds[index - 1]
        : Duration.zero;

    _cumulativeEnds[index] = previousEnd + chunkDuration;
  }

  Future<void> _restartAt(int fromIndex, {bool keepEngine = false}) async {
    if (_disposed ||
        _chunks.isEmpty ||
        fromIndex < 0 ||
        fromIndex >= _chunks.length) {
      return;
    }

    final restartGeneration = ++_generation;

    await _enqueueOperation(() async {
      if (_disposed || restartGeneration != _generation) {
        return;
      }

      _cancelled = true;
      _stopped = true;
      _prematurelyCompleted = false;

      _stallTimer?.cancel();
      _stallTimer = null;

      if (!keepEngine) {
        try {
          _engine?.invalidateSession();
        } catch (e) {
          Log.w(
            _tag,
            'Engine invalidation '
            'failed: $e',
          );
        }
      }

      try {
        await _player.stop();
      } catch (e) {
        Log.w(
          _tag,
          'Player stop during '
          'restart failed: $e',
        );
      }

      if (_disposed || restartGeneration != _generation) {
        return;
      }

      _playhead = fromIndex;
      _startedChunk = -1;
      _lastWordIndex = -1;

      _stallCount = 0;
      _stallAtChunk = -1;

      _resetChunkState(clearAudioCache: false);

      await _startPipeline(fromIndex, restartGeneration);
    });
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

      return;
    }

    while (_audioCache.length < _chunks.length) {
      _audioCache.add(null);
    }

    while (_boundaryCache.length < _chunks.length) {
      _boundaryCache.add(null);
    }

    if (_audioCache.length > _chunks.length) {
      _audioCache.removeRange(_chunks.length, _audioCache.length);
    }

    if (_boundaryCache.length > _chunks.length) {
      _boundaryCache.removeRange(_chunks.length, _boundaryCache.length);
    }
  }

  void _startStallTimer() {
    _stallTimer?.cancel();

    if (_disposed) return;

    _stallTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _cancelled || _stopped || _completed || _paused) {
        return;
      }

      if (!_player.audioPlayer.playing) {
        return;
      }

      // Slow synthesis is not itself a playback stall.
      if (_synthesizing) {
        return;
      }

      final now = DateTime.now();

      final noBytes = now.difference(_lastBytesAt) > stallTimeout;

      final noProgress = now.difference(_lastPositionAt) > stallTimeout;

      if (!noBytes || !noProgress) {
        return;
      }

      if (_stallAtChunk != _playhead) {
        _stallAtChunk = _playhead;
        _stallCount = 0;
      }

      ++_stallCount;

      if (_stallCount >= maxStallRestarts) {
        Log.e(
          _tag,
          'Giving up on chunk '
          '$_playhead after '
          '$_stallCount stalls',
        );

        _stallTimer?.cancel();
        _stallTimer = null;
        _pipelineFailed = true;

        onError?.call(
          StateError(
            'Chunk $_playhead will not '
            'play after $_stallCount '
            'consecutive stalls',
          ),
          fatal: true,
        );

        unawaited(_stopInternal(invalidateEngine: true));

        return;
      }

      Log.w(
        _tag,
        'Stall detected at chunk '
        '$_playhead '
        '(attempt $_stallCount)',
      );

      onError?.call(StateError('Synthesis stalled'), fatal: false);

      unawaited(_restartAt(_playhead, keepEngine: _stallCount == 1));
    });
  }

  void _onPlayerState(ProcessingState processingState) {
    if (processingState != ProcessingState.completed) {
      return;
    }

    if (_disposed || _cancelled || _stopped || _completed) {
      return;
    }

    if (_pipelineFailed) {
      unawaited(_stopInternal(invalidateEngine: true));
      return;
    }

    final loaded = _player.playlistLength;

    // Determine whether the current playlist covered every chunk that still
    // had to be appended. The playlist spans [_pipelineFromIndex,
    // _pipelineFromIndex + loaded); if it reaches the last chunk of the
    // session, the player genuinely reached the end.
    final lastLoadedChunk = _pipelineFromIndex + loaded - 1;
    final sessionEnded = lastLoadedChunk >= _chunks.length - 1;

    if (!sessionEnded) {
      Log.w(
        _tag,
        'Player completed playlist at '
        'chunk $_playhead before all '
        'chunks loaded '
        '(loaded=$loaded/'
        '${_chunks.length}, '
        'synthesizing=$_synthesizing)',
      );

      _prematurelyCompleted = true;

      if (!_synthesizing) {
        _handlePrematureCompletion();
      }

      return;
    }

    _finishSession();
  }

  void _handlePrematureCompletion() {
    if (_prematureAtChunk != _playhead) {
      _prematureAtChunk = _playhead;
      _prematureCount = 0;
    }

    ++_prematureCount;

    if (_prematureCount >= maxStallRestarts) {
      Log.e(
        _tag,
        'Giving up on chunk '
        '$_playhead after '
        '$_prematureCount restarts',
      );

      _stallTimer?.cancel();
      _stallTimer = null;
      _pipelineFailed = true;

      onError?.call(
        StateError(
          'Chunk $_playhead will not play '
          'after $_prematureCount '
          'consecutive restarts',
        ),
        fatal: true,
      );

      unawaited(_stopInternal(invalidateEngine: true));

      return;
    }

    Log.w(
      _tag,
      'Premature completion at chunk '
      '$_playhead '
      '(attempt $_prematureCount)',
    );

    onError?.call(StateError('Playback stalled'), fatal: false);

    unawaited(_restartAt(_playhead, keepEngine: _prematureCount == 1));
  }

  void _onPosition(Duration position) {
    if (_disposed || _cancelled || _stopped || _completed) {
      return;
    }

    _lastPositionAt = DateTime.now();

    // Any position event proves the player is making progress.
    _stallCount = 0;
    _stallAtChunk = -1;

    if (_chunks.isEmpty) {
      return;
    }

    if (_playhead < 0 || _playhead >= _chunks.length) {
      return;
    }

    final itemIndex = _player.audioPlayer.currentIndex;

    if (itemIndex == null) {
      return;
    }

    final rawChunk = itemIndex + _pipelineFromIndex;

    final chunk = rawChunk.clamp(_pipelineFromIndex, _chunks.length - 1);

    if (chunk > _playhead) {
      while (_playhead < chunk && _playhead < _chunks.length) {
        _fireTrailingWords(_playhead);

        onChunkCompleted?.call(_playhead);

        ++_playhead;

        _lastWordIndex = -1;
        _startedChunk = -1;
      }

      // Actual forward playback invalidates premature-completion counters.
      _prematureCount = 0;
      _prematureAtChunk = -1;
    } else if (chunk < _playhead) {
      // LoopMode.all wrapped back to an earlier playlist item.
      _playhead = chunk;

      _lastWordIndex = -1;
      _startedChunk = -1;
    }

    if (_startedChunk != _playhead) {
      _startedChunk = _playhead;

      onChunkStart?.call(_playhead);
    }

    final boundaries = _playhead < _boundaries.length
        ? _boundaries[_playhead]
        : null;

    if (boundaries == null || boundaries.isEmpty || position.isNegative) {
      return;
    }

    var wordIndex = -1;

    for (var i = boundaries.length - 1; i >= 0; i--) {
      if (position >= boundaries[i].offset) {
        wordIndex = i;
        break;
      }
    }

    if (wordIndex == -1 || wordIndex <= _lastWordIndex) {
      return;
    }

    for (var i = _lastWordIndex + 1; i <= wordIndex; i++) {
      onWord?.call(_playhead, i);
    }

    _lastWordIndex = wordIndex;
  }

  void _fireTrailingWords(int index) {
    final boundaries = index < _boundaries.length ? _boundaries[index] : null;

    if (boundaries == null || boundaries.isEmpty) {
      return;
    }

    final first = (_lastWordIndex + 1).clamp(0, boundaries.length);

    for (var i = first; i < boundaries.length; i++) {
      onWord?.call(index, i);
    }
  }

  void _finishSession() {
    if (_completed || _disposed) {
      return;
    }

    _completed = true;
    _cancelled = true;
    _stopped = true;

    _stallTimer?.cancel();
    _stallTimer = null;

    while (_playhead < _chunks.length) {
      _fireTrailingWords(_playhead);

      onChunkCompleted?.call(_playhead);

      ++_playhead;
      _lastWordIndex = -1;
    }

    unawaited(_player.stop());

    onCompleted?.call();
  }

  bool _isGenerationCurrent(int generation) {
    return !_disposed && generation == _generation && !_cancelled;
  }

  Future<void> _enqueueOperation(Future<void> Function() operation) {
    final next = _operationQueue.then((_) => operation());

    // Keep the queue alive even if one operation fails.
    _operationQueue = next.catchError((Object error, StackTrace stack) {
      // Right now, I don't wanna touch the loggin. Later on, what, later on, we will add stack, stack as an  optional argument
      Log.e(_tag, 'Controller operation failed', '$error\n$stack');
    });

    return next;
  }

  Future<void> disposeAsync() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    ++_generation;

    _cancelled = true;
    _stopped = true;
    _paused = false;

    _stallTimer?.cancel();
    _stallTimer = null;

    await _processingStateSub.cancel();
    await _positionSub.cancel();

    try {
      await _player.stop();
    } catch (_) {}

    final engine = _engine;
    _engine = null;

    if (engine != null) {
      try {
        engine.invalidateSession();
      } catch (_) {}

      try {
        await engine.close();
      } catch (_) {}
    }
  }

  void dispose() {
    unawaited(disposeAsync());
  }
}
