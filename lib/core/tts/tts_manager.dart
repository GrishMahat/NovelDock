import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import 'background_audio_handler.dart';
import 'chunker.dart';
import 'controller.dart';
import 'engine/edge_tts_engine.dart';
import 'engine/tts_engine.dart';
import 'tts_mpris.dart';
import '../utils/logger.dart';

const _tag = 'TtsManager';

enum TtsHighlightMode { paragraph, sentence, word }

class TtsManagerState {
  final bool isSpeaking;
  final bool isPaused;
  /// Paragraph index being synthesized/played (for display mapping).
  final int currentChunkIndex;
  /// Word index within the current paragraph's plain text (for highlighting).
  final int currentWordIndex;
  final int totalChunks;
  final double speed;
  final double pitch;
  final String voice;
  final String language;
  /// Plain text of the current paragraph — used for notifications.
  final String currentText;
  final String novelTitle;
  final String novelAuthor;
  final TtsHighlightMode highlightMode;
  final Duration totalDuration;

  const TtsManagerState({
    this.isSpeaking = false,
    this.isPaused = false,
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
  });

  int get currentLineIndex => currentChunkIndex;
  int get totalLines => totalChunks;

  TtsManagerState copyWith({
    bool? isSpeaking,
    bool? isPaused,
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
  }) {
    return TtsManagerState(
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isPaused: isPaused ?? this.isPaused,
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
    );
  }
}

class TtsManager extends StateNotifier<TtsManagerState> {
  final Ref ref;
  final EdgeTtsEngine _engine = EdgeTtsEngine();
  final TtsPlaybackController _controller = TtsPlaybackController();
  bool _notificationsInitialized = false;

  /// Paragraph-level display texts — one entry per paragraph.
  List<String> _chunkTexts = [];

  /// TTS chunks — the actual synthesis/playback units.
  List<TtsChunk> _ttsChunks = [];

  int _totalParagraphs = 0;

  List<String> get lines => _chunkTexts;

  TtsManager(this.ref) : super(const TtsManagerState()) {
    _loadSettings();
  }

  static const _defaultVoice = 'en-US-BrianMultilingualNeural';

  Future<void> _ensureNotifications() async {
    if (_notificationsInitialized) return;
    _notificationsInitialized = true;

    audioHandler ??= await initAudioService();
    audioHandler!.onPlay = () => resume();
    audioHandler!.onPause = () => pause();
    audioHandler!.onStop = () => stop();
    audioHandler!.onSkipNext = () => skipForward();
    audioHandler!.onSkipPrevious = () => skipBackward();
    audioHandler!.onSeek = (position) => _controller.seekTo(position);
    audioHandler!.onSeekForward = () => skipForward();
    audioHandler!.onSeekBackward = () => skipBackward();

    await TtsMpris.init();
    TtsMpris.onPlay = () => resume();
    TtsMpris.onPause = () => pause();
    TtsMpris.onStop = () => stop();
    TtsMpris.onNext = () => skipForward();
    TtsMpris.onPrevious = () => skipBackward();
  }

  void _updateMedia() {
    if (!state.isSpeaking && !state.isPaused) {
      TtsMpris.hide();
      if (audioHandler != null) {
        audioHandler!.dismiss();
      }
      return;
    }
    final isPlaying = state.isSpeaking && !state.isPaused;
    final novelTitle = state.novelTitle.isNotEmpty ? state.novelTitle : 'NovelDock';
    final author = state.novelAuthor.isNotEmpty ? state.novelAuthor : 'NovelDock';
    final currentText = state.currentText.isNotEmpty ? state.currentText : 'Reading...';
    final position = _controller.position;
    final duration = _controller.totalDuration;

    TtsMpris.updateState(
      title: novelTitle,
      artist: author,
      isPlaying: isPlaying,
      position: position,
      duration: duration,
    );

    if (audioHandler != null) {
      audioHandler!.updateMediaInfo(
        title: novelTitle,
        artist: '$currentText (${state.currentChunkIndex + 1}/${state.totalChunks})',
        isPlaying: isPlaying,
        position: position,
        duration: duration,
      );
    }
  }

  Future<void> _loadSettings() async {
    final p = await SharedPreferences.getInstance();
    final modeIndex = p.getInt('tts_highlight_mode') ?? 1;
    state = state.copyWith(
      speed: p.getDouble('tts_speed') ?? 1.0,
      pitch: p.getDouble('tts_pitch') ?? 1.0,
      voice: p.getString('tts_voice') ?? '',
      language: p.getString('tts_language') ?? 'en-US',
      highlightMode: TtsHighlightMode.values[modeIndex.clamp(0, 2)],
    );
  }

  Future<void> _saveSettings() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('tts_speed', state.speed);
    await p.setDouble('tts_pitch', state.pitch);
    await p.setString('tts_voice', state.voice);
    await p.setString('tts_language', state.language);
    await p.setInt('tts_highlight_mode', state.highlightMode.index);
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

  /// Find the first TTS chunk index belonging to a given paragraph.
  int _findFirstChunkOfParagraph(int paragraphIndex) {
    for (int i = 0; i < _ttsChunks.length; i++) {
      if (_ttsChunks[i].paragraphIndex == paragraphIndex) return i;
    }
    return -1;
  }

  void _wireController() {
    _controller.onChunkStart = (chunkIndex) {
      if (chunkIndex >= _ttsChunks.length) return;
      final paraIdx = _ttsChunks[chunkIndex].paragraphIndex;
      if (paraIdx < _chunkTexts.length) {
        state = state.copyWith(
          currentChunkIndex: paraIdx,
          currentWordIndex: 0,
          currentText: _chunkTexts[paraIdx],
        );
      }
      _updateMedia();
    };
    _controller.onWord = (chunkIndex, wordIndex) {
      if (chunkIndex >= _ttsChunks.length) return;
      final chunk = _ttsChunks[chunkIndex];
      state = state.copyWith(
        currentChunkIndex: chunk.paragraphIndex,
        currentWordIndex: chunk.paragraphWordOffset + wordIndex,
      );
    };
    _controller.onCompleted = () {
      state = state.copyWith(isSpeaking: false, isPaused: false);
      _updateMedia();
    };
    _controller.onError = (error, {required bool fatal}) {
      Log.e(_tag, 'TTS error: $error (fatal: $fatal)');
      if (fatal) {
        state = state.copyWith(isSpeaking: false, isPaused: false);
        _updateMedia();
      }
    };
  }

  /// Start TTS from a list of paragraph texts.
  Future<void> startFromParagraphs(
    List<String> paragraphs, {
    int startParagraph = 0,
    String? coverUrl,
    String? novelTitle,
    String? novelAuthor,
  }) async {
    if (paragraphs.isEmpty) return;
    if (state.isSpeaking || state.isPaused) return;

    _chunkTexts = paragraphs;
    _totalParagraphs = paragraphs.length;

    _ttsChunks = TtsChunker().chunkParagraphs(paragraphs, speed: state.speed);
    if (_ttsChunks.isEmpty) return;

    final startChunk = _findFirstChunkOfParagraph(
      startParagraph.clamp(0, _totalParagraphs - 1),
    );
    if (startChunk < 0) return;

    final totalChars = paragraphs.fold(0, (s, t) => s + t.length);
    final estimatedSeconds = (totalChars / 15.0 / state.speed).round();

    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      currentChunkIndex: startParagraph.clamp(0, _totalParagraphs - 1),
      currentWordIndex: 0,
      totalChunks: _totalParagraphs,
      currentText: paragraphs[state.currentChunkIndex],
      novelTitle: novelTitle ?? '',
      novelAuthor: novelAuthor ?? '',
      totalDuration: Duration(seconds: estimatedSeconds),
    );

    await _ensureNotifications();

    if (coverUrl != null) {
      await TtsMpris.setCoverArt(coverUrl);
    }

    _wireController();
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

    _updateMedia();
  }

  Future<void> pause() async {
    await _controller.pause();
    state = state.copyWith(isPaused: true);
    _updateMedia();
  }

  Future<void> resume() async {
    await _controller.resume();
    state = state.copyWith(isPaused: false);
    _updateMedia();
  }

  Future<void> togglePause() async {
    if (state.isSpeaking && !state.isPaused) {
      await pause();
    } else if (state.isPaused) {
      await resume();
    }
  }

  bool _stopping = false;

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    try {
      await _controller.stop();
      state = state.copyWith(
        isSpeaking: false,
        isPaused: false,
        currentChunkIndex: 0,
        currentText: '',
      );
      _chunkTexts = [];
      _ttsChunks = [];
      _totalParagraphs = 0;
      _updateMedia();
    } finally {
      _stopping = false;
    }
  }

  Future<void> skipForward() async {
    final nextParagraph = state.currentChunkIndex + 1;
    if (nextParagraph >= _totalParagraphs) return;
    final chunkIndex = _findFirstChunkOfParagraph(nextParagraph);
    if (chunkIndex < 0) return;
    await _controller.skipTo(chunkIndex);
  }

  Future<void> skipBackward() async {
    // First press restarts the current chunk; second press goes back a
    // paragraph.
    if (_controller.position > const Duration(seconds: 2)) {
      await _controller.restartCurrent();
      return;
    }
    final prevParagraph = state.currentChunkIndex - 1;
    if (prevParagraph < 0) return;
    final chunkIndex = _findFirstChunkOfParagraph(prevParagraph);
    if (chunkIndex < 0) return;
    await _controller.skipTo(chunkIndex);
  }

  Future<void> updateSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _controller.setSpeed(speed);
    await _controller.setRate(_rateString());
    await _saveSettings();
  }

  Future<void> updatePitch(double pitch) async {
    state = state.copyWith(pitch: pitch);
    await _controller.setPitch(_pitchString());
    await _saveSettings();
  }

  Future<void> updateVoice(String voice) async {
    state = state.copyWith(voice: voice);
    await _saveSettings();
  }

  Future<void> updateLanguage(String language) async {
    state = state.copyWith(language: language);
    await _saveSettings();
  }

  Future<void> updateHighlightMode(TtsHighlightMode mode) async {
    state = state.copyWith(highlightMode: mode);
    await _saveSettings();
  }

  Future<List<TtsEngineVoice>> getVoices() async {
    return _engine.getVoices();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

final ttsManagerProvider = StateNotifierProvider<TtsManager, TtsManagerState>((ref) {
  return TtsManager(ref);
});
