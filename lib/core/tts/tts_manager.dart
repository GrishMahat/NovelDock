import 'dart:async';

import 'package:anni_mpris_service/anni_mpris_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import 'background_audio_handler.dart';
import 'chunker.dart';
import 'controller.dart';
import 'engine/edge_tts_engine.dart';
import 'engine/system_tts_engine.dart';
import 'engine/tts_engine.dart';
import 'tts_mpris.dart';
import '../utils/logger.dart';

const _tag = 'TtsManager';

enum TtsHighlightMode { paragraph, sentence, word }

class TtsManagerState {
  final bool isSpeaking;
  final bool isPaused;

  /// Active synthesis engine id ('edge' or 'system').
  final String engineId;

  /// Paragraph index being synthesized/played.
  final int currentChunkIndex;

  /// Word index within the current paragraph's plain text.
  final int currentWordIndex;

  final int totalChunks;
  final double speed;
  final double pitch;
  final String voice;
  final String language;

  /// Plain text of the current paragraph.
  final String currentText;

  final String novelTitle;
  final String novelAuthor;
  final TtsHighlightMode highlightMode;
  final Duration totalDuration;

  /// True only when every chunk finished naturally.
  final bool completedNaturally;

  const TtsManagerState({
    this.isSpeaking = false,
    this.isPaused = false,
    this.engineId = 'edge',
    this.currentChunkIndex = 0,
    this.currentWordIndex = 0,
    this.totalChunks = 0,
    this.speed = 1.0,
    this.pitch = 1.0,
    this.voice = '',
    this.language = 'en-US',
    this.currentText = '',
    this.novelTitle = '',
    this.novelAuthor = '',
    this.highlightMode = TtsHighlightMode.sentence,
    this.totalDuration = Duration.zero,
    this.completedNaturally = false,
  });

  int get currentLineIndex => currentChunkIndex;
  int get totalLines => totalChunks;

  TtsManagerState copyWith({
    bool? isSpeaking,
    bool? isPaused,
    String? engineId,
    int? currentChunkIndex,
    int? currentWordIndex,
    int? totalChunks,
    double? speed,
    double? pitch,
    String? voice,
    String? language,
    String? currentText,
    String? novelTitle,
    String? novelAuthor,
    TtsHighlightMode? highlightMode,
    Duration? totalDuration,
    bool? completedNaturally,
  }) {
    return TtsManagerState(
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isPaused: isPaused ?? this.isPaused,
      engineId: engineId ?? this.engineId,
      currentChunkIndex: currentChunkIndex ?? this.currentChunkIndex,
      currentWordIndex: currentWordIndex ?? this.currentWordIndex,
      totalChunks: totalChunks ?? this.totalChunks,
      speed: speed ?? this.speed,
      pitch: pitch ?? this.pitch,
      voice: voice ?? this.voice,
      language: language ?? this.language,
      currentText: currentText ?? this.currentText,
      novelTitle: novelTitle ?? this.novelTitle,
      novelAuthor: novelAuthor ?? this.novelAuthor,
      highlightMode: highlightMode ?? this.highlightMode,
      totalDuration: totalDuration ?? this.totalDuration,
      completedNaturally: completedNaturally ?? this.completedNaturally,
    );
  }
}

class TtsManager extends StateNotifier<TtsManagerState> {
  final Ref ref;

  TtsEngine _engine = EdgeTtsEngine();
  final TtsPlaybackController _controller = TtsPlaybackController();

  /// The engine synthesis and voice discovery currently go through.
  TtsEngine get activeEngine => _engine;

  static TtsEngine _buildEngine(String id) {
    if (id == 'system' && SystemTtsEngine.isSupported) {
      return SystemTtsEngine();
    }
    return EdgeTtsEngine();
  }

  /// Switches the synthesis engine. Stops any active playback first and
  /// resets the stored voice (voice ids are engine-specific).
  Future<void> setTtsEngine(String id) async {
    var target = id == 'system' ? 'system' : 'edge';
    if (target == state.engineId && _engine.id == target) return;

    if (state.isSpeaking || state.isPaused) {
      await stop();
    }

    await _engine.close();

    var next = _buildEngine(target);
    try {
      await next.init();
    } catch (e) {
      Log.e(_tag, 'Failed to init $target engine; falling back to edge', e);
      next = EdgeTtsEngine();
      await next.init();
      target = 'edge';
    }
    _engine = next;

    // Voice ids are engine-specific; clear so a valid default is picked.
    state = state.copyWith(engineId: target, voice: '');

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('tts_engine', target);
      await preferences.setString('tts_voice', '');
    } catch (e) {
      Log.e(_tag, 'Failed to persist tts_engine', e);
    }
  }

  bool _notificationsInitialized = false;
  Future<void>? _notificationsInitFuture;

  /// Guards asynchronous session replacement.
  int _sessionGeneration = 0;

  /// Prevents overlapping stop operations.
  bool _stopping = false;

  /// Prevents settings load from overwriting changes made by the user while
  /// SharedPreferences was still being initialized.
  int _settingsMutationVersion = 0;

  /// Serializes settings writes.
  Future<void> _settingsSaveQueue = Future<void>.value();

  /// Paragraph-level display texts.
  List<String> _chunkTexts = [];

  /// Actual TTS chunks.
  List<TtsChunk> _ttsChunks = [];

  int _totalParagraphs = 0;

  List<String> get lines => List.unmodifiable(_chunkTexts);

  static const _defaultVoice = 'en-US-BrianMultilingualNeural';

  TtsManager(this.ref) : super(const TtsManagerState()) {
    _loadSettings();
  }

  Future<void> _ensureNotifications() async {
    if (_notificationsInitialized) return;

    final existing = _notificationsInitFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final future = _initializeNotifications();

    _notificationsInitFuture = future;

    try {
      await future;
    } finally {
      // Allow retry after a failed initialization.
      if (identical(_notificationsInitFuture, future)) {
        _notificationsInitFuture = null;
      }
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      audioHandler ??= await initAudioService();

      final handler = audioHandler;
      if (handler == null) {
        throw StateError('Audio service returned no handler');
      }

      handler.onPlay = () => unawaited(resume());
      handler.onPause = () => unawaited(pause());
      handler.onStop = () => unawaited(stop());
      handler.onSkipNext = () => unawaited(skipForward());
      handler.onSkipPrevious = () => unawaited(skipBackward());
      handler.onSeek = (position) => unawaited(_controller.seekTo(position));
      handler.onSeekForward = () => unawaited(skipForward());
      handler.onSeekBackward = () => unawaited(skipBackward());

      await TtsMpris.init();

      TtsMpris.onPlay = () => unawaited(resume());
      TtsMpris.onPause = () => unawaited(pause());
      TtsMpris.onStop = () => unawaited(stop());
      TtsMpris.onNext = () => unawaited(skipForward());
      TtsMpris.onPrevious = () => unawaited(skipBackward());

      TtsMpris.onLoopChange = (status) {
        unawaited(
          _controller.setLoopMode(switch (status) {
            LoopStatus.none => LoopMode.off,
            LoopStatus.track => LoopMode.one,
            LoopStatus.playlist => LoopMode.all,
          }),
        );
      };

      _notificationsInitialized = true;
    } catch (e) {
      _notificationsInitialized = false;
      Log.e(_tag, 'Failed to initialize media controls', e);
      rethrow;
    }
  }

  void _updateMedia() {
    final active = state.isSpeaking || state.isPaused;

    if (!active) {
      TtsMpris.hide();

      final handler = audioHandler;
      if (handler != null) {
        unawaited(handler.dismiss());
      }

      return;
    }

    final isPlaying = state.isSpeaking && !state.isPaused;

    final title = state.novelTitle.isNotEmpty ? state.novelTitle : 'NovelDock';

    final author = state.novelAuthor.isNotEmpty
        ? state.novelAuthor
        : 'NovelDock';

    final currentText = state.currentText.isNotEmpty
        ? state.currentText
        : 'Reading...';

    final position = _controller.position;
    final duration = _controller.totalDuration;

    TtsMpris.updateState(
      title: title,
      artist: author,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
    );

    final handler = audioHandler;
    if (handler != null) {
      handler.updateMediaInfo(
        title: title,
        artist:
            '$currentText '
            '(${state.currentChunkIndex + 1}'
            '/${state.totalChunks})',
        isPlaying: isPlaying,
        position: position,
        duration: duration,
      );
    }
  }

  Future<void> _loadSettings() async {
    try {
      final preferences = await SharedPreferences.getInstance();

      final versionAtStart = _settingsMutationVersion;

      final rawMode = preferences.getInt('tts_highlight_mode') ?? 1;

      final modeIndex = rawMode.clamp(0, TtsHighlightMode.values.length - 1);

      // Restore the saved engine (falling back when unsupported on this
      // platform) before any voice/language value is consumed.
      var engineId = preferences.getString('tts_engine') ?? 'edge';
      if (engineId != _engine.id) {
        if (engineId == 'system' && !SystemTtsEngine.isSupported) {
          Log.w(_tag, 'System TTS unavailable here; using edge');
          engineId = 'edge';
        }
        final previous = _engine;
        _engine = _buildEngine(engineId);
        try {
          await _engine.init();
        } catch (e) {
          Log.e(_tag, 'Restored engine init failed; keeping edge', e);
          _engine = previous;
          engineId = _engine.id;
        }
      }

      // Do not overwrite a setting modified while the async load
      // was in progress.
      if (versionAtStart != _settingsMutationVersion) {
        return;
      }

      state = state.copyWith(
        engineId: engineId,
        speed: preferences.getDouble('tts_speed') ?? 1.0,
        pitch: preferences.getDouble('tts_pitch') ?? 1.0,
        voice: preferences.getString('tts_voice') ?? '',
        language: preferences.getString('tts_language') ?? 'en-US',
        highlightMode: TtsHighlightMode.values[modeIndex],
      );
    } catch (e) {
      Log.e(_tag, 'Failed to load TTS settings', e);
    }
  }

  Future<void> _saveSettings() {
    final snapshot = state;
    final version = ++_settingsMutationVersion;

    _settingsSaveQueue = _settingsSaveQueue.then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();

        await preferences.setDouble('tts_speed', snapshot.speed);
        await preferences.setDouble('tts_pitch', snapshot.pitch);
        await preferences.setString('tts_voice', snapshot.voice);
        await preferences.setString('tts_language', snapshot.language);
        await preferences.setInt(
          'tts_highlight_mode',
          snapshot.highlightMode.index,
        );

        // Version is intentionally captured to document the snapshot
        // semantics. A later mutation simply gets its own queued write.
        if (version != _settingsMutationVersion) {
          return;
        }
      } catch (e) {
        Log.e(_tag, 'Failed to save TTS settings', e);
      }
    });

    return _settingsSaveQueue;
  }

  String get _voiceId => state.voice.isEmpty ? _defaultVoice : state.voice;

  String _rateString() {
    final percent = ((state.speed - 1.0) * 100).round();

    return percent >= 0 ? '+$percent%' : '$percent%';
  }

  String _pitchString() {
    final percent = ((state.pitch - 1.0) * 50).round();

    return percent >= 0 ? '+$percent%' : '$percent%';
  }

  int _findFirstChunkOfParagraph(int paragraphIndex) {
    for (var i = 0; i < _ttsChunks.length; i++) {
      if (_ttsChunks[i].paragraphIndex == paragraphIndex) {
        return i;
      }
    }

    return -1;
  }

  int _clampParagraph(int index) {
    if (_totalParagraphs <= 0) return 0;

    return index.clamp(0, _totalParagraphs - 1);
  }

  void _wireController(int generation) {
    _controller.onChunkStart = (chunkIndex) {
      if (generation != _sessionGeneration) {
        return;
      }

      if (chunkIndex < 0 || chunkIndex >= _ttsChunks.length) {
        return;
      }

      final paragraphIndex = _ttsChunks[chunkIndex].paragraphIndex;

      if (paragraphIndex < 0 || paragraphIndex >= _chunkTexts.length) {
        return;
      }

      state = state.copyWith(
        currentChunkIndex: paragraphIndex,
        currentWordIndex: 0,
        currentText: _chunkTexts[paragraphIndex],
      );

      // Playback reached what we optimistically skipped to.
      if (_skipAnchor != null && paragraphIndex >= _skipAnchor!) {
        _skipAnchor = null;
      }

      _updateMedia();
    };

    _controller.onWord = (chunkIndex, wordIndex) {
      if (generation != _sessionGeneration) {
        return;
      }

      if (chunkIndex < 0 || chunkIndex >= _ttsChunks.length) {
        return;
      }

      final chunk = _ttsChunks[chunkIndex];

      state = state.copyWith(
        currentChunkIndex: chunk.paragraphIndex,
        currentWordIndex: chunk.paragraphWordOffset + wordIndex,
      );
    };

    _controller.onCompleted = () {
      if (generation != _sessionGeneration) {
        return;
      }

      state = state.copyWith(
        isSpeaking: false,
        isPaused: false,
        completedNaturally: true,
      );

      _updateMedia();
    };

    _controller.onError = (error, {required bool fatal}) {
      if (generation != _sessionGeneration) {
        return;
      }

      Log.e(
        _tag,
        'TTS error: $error '
        '(fatal: $fatal)',
      );

      if (!fatal) return;

      state = state.copyWith(
        isSpeaking: false,
        isPaused: false,
        completedNaturally: false,
      );

      _updateMedia();
    };
  }

  /// Starts TTS from a list of paragraph texts.
  Future<void> startFromParagraphs(
    List<String> paragraphs, {
    int startParagraph = 0,
    String? coverUrl,
    String? novelTitle,
    String? novelAuthor,
  }) async {
    if (paragraphs.isEmpty) return;

    if (state.isSpeaking || state.isPaused) {
      return;
    }

    final generation = ++_sessionGeneration;

    _chunkTexts = List<String>.from(paragraphs);
    _totalParagraphs = _chunkTexts.length;

    _ttsChunks = TtsChunker().chunkParagraphs(_chunkTexts, speed: state.speed);

    if (_ttsChunks.isEmpty) {
      _clearSessionState();
      return;
    }

    final paragraph = _clampParagraph(startParagraph);

    final startChunk = _findFirstChunkOfParagraph(paragraph);

    if (startChunk < 0) {
      _clearSessionState();
      return;
    }

    final totalChars = _chunkTexts.fold<int>(
      0,
      (sum, text) => sum + text.length,
    );

    final estimatedSeconds = (totalChars / 15.0 / state.speed).round();

    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      currentChunkIndex: paragraph,
      currentWordIndex: 0,
      totalChunks: _totalParagraphs,
      currentText: _chunkTexts[paragraph],
      novelTitle: novelTitle ?? '',
      novelAuthor: novelAuthor ?? '',
      totalDuration: Duration(seconds: estimatedSeconds),
      completedNaturally: false,
    );

    try {
      await _ensureNotifications();

      // The request may have been stopped/replaced while notification
      // initialization was in progress.
      if (generation != _sessionGeneration) {
        return;
      }

      if (coverUrl != null) {
        await TtsMpris.setCoverArt(coverUrl);
      }

      if (generation != _sessionGeneration) {
        return;
      }

      _wireController(generation);

      await _controller.start(
        chunks: _ttsChunks,
        engine: _engine,
        voiceId: _voiceId,
        rate: _rateString(),
        pitch: _pitchString(),
        locale: state.language,
        startIndex: startChunk,
        speed: state.speed,
      );

      if (generation != _sessionGeneration) {
        return;
      }

      _updateMedia();
    } catch (e) {
      if (generation != _sessionGeneration) {
        return;
      }

      Log.e(_tag, 'Failed to start TTS', e);

      state = state.copyWith(
        isSpeaking: false,
        isPaused: false,
        completedNaturally: false,
      );

      _updateMedia();

      rethrow;
    }
  }

  Future<void> pause() async {
    if (!state.isSpeaking || state.isPaused) {
      return;
    }

    await _controller.pause();

    if (!state.isSpeaking) return;

    state = state.copyWith(isPaused: true);

    _updateMedia();
  }

  Future<void> resume() async {
    if (!state.isSpeaking || !state.isPaused) {
      return;
    }

    await _controller.resume();

    if (!state.isSpeaking) return;

    state = state.copyWith(isPaused: false);

    _updateMedia();
  }

  Future<void> togglePause() async {
    if (state.isSpeaking && !state.isPaused) {
      await pause();
    } else if (state.isSpeaking && state.isPaused) {
      await resume();
    }
  }

  Future<void> stop() async {
    if (_stopping) return;

    _stopping = true;

    // Invalidate every callback belonging to the previous session before
    // touching the controller.
    ++_sessionGeneration;

    try {
      await _controller.stop();

      state = state.copyWith(
        isSpeaking: false,
        isPaused: false,
        currentChunkIndex: 0,
        currentWordIndex: 0,
        totalChunks: 0,
        currentText: '',
        totalDuration: Duration.zero,
        novelTitle: '',
        novelAuthor: '',
        completedNaturally: false,
      );

      _chunkTexts = [];
      _ttsChunks = [];
      _totalParagraphs = 0;

      TtsMpris.setCoverArt(null);

      _updateMedia();
    } finally {
      _stopping = false;
    }
  }

  /// Jumps to the first chunk of [paragraphIndex], preserving paused state:
  /// a skip while paused re-positions silently instead of resuming audio.
  /// Optimistic skip target while a burst of presses is catching up.
  int? _skipAnchor;

  /// Paragraph index skips accumulate against until playback catches up.
  int get _skipBase => _skipAnchor ?? state.currentChunkIndex;

  /// Jumps toward [target], keeping the visible paragraph in sync instantly
  /// so rapid presses accumulate instead of repeating the same jump. The
  /// engine session is kept alive between skips; playback catches up in the
  /// background and clears [_skipAnchor] via onChunkStart.
  Future<void> _applySkip(int target) async {
    _skipAnchor = target;

    final wasPaused = state.isPaused;

    state = state.copyWith(
      currentChunkIndex: target,
      currentWordIndex: 0,
      currentText: target < _chunkTexts.length ? _chunkTexts[target] : null,
    );

    final chunkIndex = _findFirstChunkOfParagraph(target);

    if (chunkIndex < 0) return;

    await _controller.skipTo(chunkIndex, keepEngine: true);

    if (wasPaused) {
      await _controller.pause();
      state = state.copyWith(isPaused: true);
    }
  }

  Future<void> skipForward() async {
    if (!state.isSpeaking || _totalParagraphs <= 0) {
      return;
    }

    final target = _skipBase + 1;

    if (target >= _totalParagraphs) {
      return;
    }

    await _applySkip(target);
  }

  Future<void> skipBackward() async {
    if (!state.isSpeaking || _totalParagraphs <= 0) {
      return;
    }

    if (_controller.position > const Duration(seconds: 2)) {
      await _controller.restartCurrent();
      return;
    }

    final target = _skipBase - 1;

    if (target < 0) {
      return;
    }

    await _applySkip(target);
  }

  Future<void> updateSpeed(double speed) async {
    if (speed <= 0) return;

    _settingsMutationVersion++;

    state = state.copyWith(speed: speed);

    await _controller.setSpeed(speed);
    await _controller.setRate(_rateString());

    await _saveSettings();
  }

  Future<void> updatePitch(double pitch) async {
    _settingsMutationVersion++;

    state = state.copyWith(pitch: pitch);

    await _controller.setPitch(_pitchString());

    await _saveSettings();
  }

  Future<void> updateVoice(String voice) async {
    _settingsMutationVersion++;

    state = state.copyWith(voice: voice.trim());

    await _saveSettings();
  }

  Future<void> updateLanguage(String language) async {
    _settingsMutationVersion++;

    state = state.copyWith(
      language: language.trim().isEmpty ? 'en-US' : language.trim(),
    );

    await _saveSettings();
  }

  Future<void> updateHighlightMode(TtsHighlightMode mode) async {
    _settingsMutationVersion++;

    state = state.copyWith(highlightMode: mode);

    await _saveSettings();
  }

  Future<List<TtsEngineVoice>> getVoices() async {
    return _engine.getVoices();
  }

  void _clearSessionState() {
    _skipAnchor = null;

    state = state.copyWith(
      isSpeaking: false,
      isPaused: false,
      currentChunkIndex: 0,
      currentWordIndex: 0,
      totalChunks: 0,
      currentText: '',
      totalDuration: Duration.zero,
      completedNaturally: false,
    );

    _chunkTexts = [];
    _ttsChunks = [];
    _totalParagraphs = 0;
  }

  @override
  void dispose() {
    ++_sessionGeneration;

    _controller.dispose();
    super.dispose();
  }
}

final ttsManagerProvider = StateNotifierProvider<TtsManager, TtsManagerState>(
  (ref) => TtsManager(ref),
);
