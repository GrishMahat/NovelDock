import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart';
import 'microsoft_tts_provider.dart';
import 'tts_notification.dart';
import 'tts_mpris.dart';
import '../utils/html_chunker.dart';

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
  MicrosoftTtsProvider? _provider;

  /// Paragraph-level display texts — one entry per HTML paragraph chunk.
  List<String> _chunkTexts = [];

  /// Sentence-level TTS chunks — the actual synthesis units.
  List<TtsChunk> _ttsChunks = [];

  int _totalParagraphs = 0;

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

    await TtsMpris.init();
    TtsMpris.onPlay = () => resume();
    TtsMpris.onPause = () => pause();
    TtsMpris.onStop = () => stop();
    TtsMpris.onNext = () => skipForward();
    TtsMpris.onPrevious = () => skipBackward();

    // Wire audio_service (Android foreground service / media notification)
    audioHandler.onPlay = () => resume();
    audioHandler.onPause = () => pause();
    audioHandler.onStop = () => stop();
    audioHandler.onSkipNext = () => skipForward();
    audioHandler.onSkipPrevious = () => skipBackward();
  }

  void _updateNotification() {
    if (!state.isSpeaking && !state.isPaused) {
      TtsNotification.hide();
      TtsMpris.hide();
      audioHandler.stop();
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

    // Update audio_service notification (Android foreground service / lock screen)
    audioHandler.updateMediaInfo(
      title: novelTitle,
      artist: '$currentText (${state.currentChunkIndex + 1}/${state.totalChunks})',
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

  /// Find the first TTS chunk index belonging to a given paragraph.
  int _findFirstTtsChunkOfParagraph(int paragraphIndex) {
    for (int i = 0; i < _ttsChunks.length; i++) {
      if (_ttsChunks[i].paragraphIndex == paragraphIndex) return i;
    }
    return -1;
  }

  /// Start TTS from raw chapter HTML.
  ///
  /// Each paragraph is split into sentence-level TTS chunks (~500 chars each).
  /// All chunks are synthesized, concatenated into a single MP3, and played
  /// with one mpv process. Word boundaries are tracked with offset compensation.
  Future<void> startFromHtml(
    String html, {
    int startChunk = 0,
    String? coverUrl,
    String? novelTitle,
    String? novelAuthor,
  }) async {
    // Paragraph-level chunks for display
    final displayChunks = HtmlChunker.chunkHtml(html);
    if (displayChunks.isEmpty) return;

    _chunkTexts = displayChunks.map((c) => c.plainText).toList();
    _totalParagraphs = _chunkTexts.length;

    // Sentence-level chunks for TTS synthesis
    _ttsChunks = TtsTextChunker.chunkForTts(html);
    if (_ttsChunks.isEmpty) return;

    // Find the first TTS chunk of the starting paragraph
    final startTtsChunk = _findFirstTtsChunkOfParagraph(startChunk.clamp(0, _totalParagraphs - 1));
    if (startTtsChunk < 0) return;

    final totalChars = _chunkTexts.fold(0, (s, t) => s + t.length);
    final estimatedSeconds = (totalChars / 15.0 / state.speed).round();

    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      currentChunkIndex: startChunk.clamp(0, _totalParagraphs - 1),
      currentWordIndex: 0,
      totalChunks: _totalParagraphs,
      currentText: _chunkTexts[state.currentChunkIndex],
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

    // Synthesize sentence-level chunks, map callbacks to paragraph indices
    await _speakFromTtsChunk(startTtsChunk);

    if (state.isSpeaking) {
      state = state.copyWith(isSpeaking: false);
    }
    TtsNotification.hide();
  }

  /// Synthesize and play from a specific TTS chunk index.
  Future<void> _speakFromTtsChunk(int ttsChunkStart) async {
    if (ttsChunkStart < 0 || ttsChunkStart >= _ttsChunks.length) return;

    final texts = _ttsChunks.sublist(ttsChunkStart).map((c) => c.text).toList();

    final provider = _getProvider();
    await provider.speakAll(
      texts,
      speed: state.speed,
      pitch: state.pitch,
      onLineStart: (lineIndex) {
        if (!state.isSpeaking || state.isPaused) return;
        final absoluteIndex = ttsChunkStart + lineIndex;
        if (absoluteIndex < _ttsChunks.length) {
          final ttsChunk = _ttsChunks[absoluteIndex];
          final paraIdx = ttsChunk.paragraphIndex;
          if (paraIdx < _chunkTexts.length) {
            state = state.copyWith(
              currentChunkIndex: paraIdx,
              currentWordIndex: 0,
              currentText: _chunkTexts[paraIdx],
            );
            _updateNotification();
          }
        }
      },
      onWordStart: (lineIndex, wordIndex) {
        if (!state.isSpeaking || state.isPaused) return;
        final absoluteIndex = ttsChunkStart + lineIndex;
        if (absoluteIndex < _ttsChunks.length) {
          final ttsChunk = _ttsChunks[absoluteIndex];
          state = state.copyWith(
            currentChunkIndex: ttsChunk.paragraphIndex,
            currentWordIndex: ttsChunk.paragraphWordOffset + wordIndex,
          );
        }
      },
    );
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
    _ttsChunks = [];
    _totalParagraphs = 0;
    TtsNotification.hide();
  }

  Future<void> skipForward() async {
    final currentParagraph = state.currentChunkIndex;
    final nextParagraph = currentParagraph + 1;
    if (nextParagraph >= _totalParagraphs) return;

    final ttsChunkIndex = _findFirstTtsChunkOfParagraph(nextParagraph);
    if (ttsChunkIndex < 0) return;

    await _getProvider().stop();

    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      currentChunkIndex: nextParagraph,
      currentWordIndex: 0,
      currentText: _chunkTexts[nextParagraph],
    );
    _updateNotification();

    await _speakFromTtsChunk(ttsChunkIndex);
  }

  Future<void> skipBackward() async {
    final currentParagraph = state.currentChunkIndex;
    final prevParagraph = currentParagraph - 1;
    if (prevParagraph < 0) return;

    final ttsChunkIndex = _findFirstTtsChunkOfParagraph(prevParagraph);
    if (ttsChunkIndex < 0) return;

    await _getProvider().stop();

    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      currentChunkIndex: prevParagraph,
      currentWordIndex: 0,
      currentText: _chunkTexts[prevParagraph],
    );
    _updateNotification();

    await _speakFromTtsChunk(ttsChunkIndex);
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
