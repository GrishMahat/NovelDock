import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'microsoft_tts_provider.dart';
import 'tts_notification.dart';
import 'tts_mpris.dart';
import '../utils/html_chunker.dart';

enum TtsHighlightMode { paragraph, sentence, word }

class TtsManagerState {
  final bool isSpeaking;
  final bool isPaused;
  /// Index of the current chunk (paragraph) being synthesized/played.
  final int currentChunkIndex;
  /// Word index within the current chunk's audio (from EdgeTTS word boundary).
  final int currentWordIndex;
  final int totalChunks;
  final double speed;
  final double pitch;
  final String voice;
  final String language;
  /// Plain text of the current chunk — used only for notifications.
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

  // Keep legacy alias for any code that reads currentLineIndex
  int get currentLineIndex => currentChunkIndex;

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
  MicrosoftTtsProvider? _provider;

  /// Plain texts for each chunk — one entry per paragraph chunk.
  List<String> _chunkTexts = [];
  int _currentChunk = 0;

  List<String> get lines => _chunkTexts;

  TtsManager(this.ref) : super(const TtsManagerState()) {
    _loadSettings();
    _initNotifications();
  }

  void _initNotifications() async {
    await TtsNotification.init();
    TtsNotification.onPause = () => pause();
    TtsNotification.onResume = () => resume();
    TtsNotification.onStop = () => stop();
    TtsNotification.onSkipForward = () => skipForward();
    TtsNotification.onSkipBackward = () => skipBackward();

    // MPRIS for Linux
    await TtsMpris.init();
    TtsMpris.onPlay = () => resume();
    TtsMpris.onPause = () => pause();
    TtsMpris.onStop = () => stop();
    TtsMpris.onNext = () => skipForward();
    TtsMpris.onPrevious = () => skipBackward();
  }

  void _updateNotification() {
    if (!state.isSpeaking && !state.isPaused) {
      TtsNotification.hide();
      TtsMpris.hide();
      return;
    }
    final isPlaying = state.isSpeaking && !state.isPaused;
    final novelTitle = state.novelTitle.isNotEmpty ? state.novelTitle : 'QuickNovel';
    final author = state.novelAuthor.isNotEmpty ? state.novelAuthor : 'QuickNovel';
    final currentText = state.currentText.isNotEmpty ? state.currentText : 'Reading...';

    TtsNotification.show(
      chapterName: currentText,
      currentLine: state.currentChunkIndex + 1,
      totalLines: state.totalChunks,
      isPaused: state.isPaused,
      novelTitle: novelTitle,
    );

    final position = state.totalChunks > 0
        ? Duration(seconds: (state.totalDuration.inSeconds * state.currentChunkIndex / state.totalChunks).round())
        : Duration.zero;

    TtsMpris.updateState(
      title: novelTitle,
      artist: author,
      isPlaying: isPlaying,
      position: position,
      duration: state.totalDuration,
    );
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

  MicrosoftTtsProvider _getProvider() {
    _provider ??= MicrosoftTtsProvider();
    return _provider!;
  }

  /// Start TTS from raw chapter HTML.
  ///
  /// Each paragraph/block chunk becomes ONE synthesis request to EdgeTTS.
  /// Word boundary events within that synthesis give word-level timing for
  /// the ENTIRE paragraph — so `currentWordIndex` tracks progress through
  /// the whole paragraph, not just one sentence.
  Future<void> startFromHtml(
    String html, {
    int startChunk = 0,
    String? coverUrl,
    String? novelTitle,
    String? novelAuthor,
  }) async {
    final chunks = HtmlChunker.chunkHtml(html);
    if (chunks.isEmpty) return;

    // One entry per chunk: the full plain text of the paragraph.
    _chunkTexts = chunks.map((c) => c.plainText).toList();
    _currentChunk = startChunk.clamp(0, _chunkTexts.length - 1);

    final totalChars = _chunkTexts.fold(0, (s, t) => s + t.length);
    final estimatedSeconds = (totalChars / 15.0 / state.speed).round();

    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      currentChunkIndex: _currentChunk,
      currentWordIndex: 0,
      totalChunks: _chunkTexts.length,
      currentText: _chunkTexts[_currentChunk],
      novelTitle: novelTitle ?? '',
      novelAuthor: novelAuthor ?? '',
      totalDuration: Duration(seconds: estimatedSeconds),
    );

    final provider = _getProvider();
    await provider.init();

    if (coverUrl != null) {
      await TtsNotification.setCoverArt(coverUrl);
      await TtsMpris.setCoverArt(coverUrl);
    }
    _updateNotification();

    // speakAll receives one entry per chunk.
    // Each chunk = one synthesis call to EdgeTTS.
    // onLineStart fires when a chunk begins playing.
    // onWordStart fires for every word boundary within that chunk.
    await provider.speakAll(
      _chunkTexts.sublist(_currentChunk),
      speed: state.speed,
      pitch: state.pitch,
      onLineStart: (lineIndex) {
        if (!state.isSpeaking || state.isPaused) return;
        final actualChunk = _currentChunk + lineIndex;
        _currentChunk = actualChunk;
        if (actualChunk < _chunkTexts.length) {
          state = state.copyWith(
            currentChunkIndex: actualChunk,
            currentWordIndex: 0,
            currentText: _chunkTexts[actualChunk],
          );
          _updateNotification();
        }
      },
      onWordStart: (lineIndex, wordIndex) {
        if (!state.isSpeaking || state.isPaused) return;
        final actualChunk = _currentChunk + lineIndex;
        if (actualChunk < _chunkTexts.length) {
          state = state.copyWith(
            currentChunkIndex: actualChunk,
            currentWordIndex: wordIndex,
          );
        }
      },
    );

    if (state.isSpeaking) {
      state = state.copyWith(isSpeaking: false);
    }
    TtsNotification.hide();
  }

  Future<void> pause() async {
    await _getProvider().pause();
    state = state.copyWith(isPaused: true);
    _updateNotification();
  }

  Future<void> resume() async {
    await _getProvider().resume();
    state = state.copyWith(isPaused: false);
    _updateNotification();
  }

  Future<void> togglePause() async {
    if (state.isSpeaking && !state.isPaused) {
      await pause();
    } else if (state.isPaused) {
      await resume();
    }
  }

  Future<void> stop() async {
    await _getProvider().stop();
    state = state.copyWith(isSpeaking: false, isPaused: false, currentChunkIndex: 0, currentText: '');
    _chunkTexts = [];
    _currentChunk = 0;
    TtsNotification.hide();
  }

  Future<void> skipForward() async {
    if (_currentChunk < _chunkTexts.length - 1) {
      await _getProvider().stop();
      _currentChunk++;
      await _resumeFromChunk(_currentChunk);
    }
  }

  Future<void> skipBackward() async {
    if (_currentChunk > 0) {
      await _getProvider().stop();
      _currentChunk--;
      await _resumeFromChunk(_currentChunk);
    }
  }

  Future<void> _resumeFromChunk(int startChunk) async {
    if (startChunk < 0 || startChunk >= _chunkTexts.length) return;

    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      currentChunkIndex: startChunk,
      currentWordIndex: 0,
      currentText: _chunkTexts[startChunk],
    );
    _updateNotification();

    final provider = _getProvider();
    await provider.init();
    await provider.speakAll(
      _chunkTexts.sublist(startChunk),
      speed: state.speed,
      pitch: state.pitch,
      onLineStart: (lineIndex) {
        final actualChunk = startChunk + lineIndex;
        _currentChunk = actualChunk;
        if (actualChunk < _chunkTexts.length) {
          state = state.copyWith(
            currentChunkIndex: actualChunk,
            currentWordIndex: 0,
            currentText: _chunkTexts[actualChunk],
          );
          _updateNotification();
        }
      },
      onWordStart: (lineIndex, wordIndex) {
        final actualChunk = startChunk + lineIndex;
        if (actualChunk < _chunkTexts.length) {
          state = state.copyWith(
            currentChunkIndex: actualChunk,
            currentWordIndex: wordIndex,
          );
        }
      },
    );

    if (state.isSpeaking) {
      state = state.copyWith(isSpeaking: false);
    }
    TtsNotification.hide();
  }

  Future<void> updateSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _saveSettings();
  }

  Future<void> updatePitch(double pitch) async {
    state = state.copyWith(pitch: pitch);
    await _saveSettings();
  }

  Future<void> updateVoice(String voice) async {
    state = state.copyWith(voice: voice);
    await _getProvider().setVoice(voice);
    await _saveSettings();
  }

  Future<void> updateLanguage(String language) async {
    state = state.copyWith(language: language);
    await _getProvider().setLanguage(language);
    await _saveSettings();
  }

  Future<void> updateHighlightMode(TtsHighlightMode mode) async {
    state = state.copyWith(highlightMode: mode);
    await _saveSettings();
  }

  Future<List<EdgeTtsVoice>> getVoices() async {
    final provider = _getProvider();
    await provider.init();
    return provider.getVoices();
  }
}

final ttsManagerProvider = StateNotifierProvider<TtsManager, TtsManagerState>((ref) {
  return TtsManager(ref);
});
