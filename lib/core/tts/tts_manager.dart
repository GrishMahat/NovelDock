import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'microsoft_tts_provider.dart';
import 'tts_notification.dart';
import 'tts_mpris.dart';

enum TtsHighlightMode { paragraph, sentence, word }

class TtsManagerState {
  final bool isSpeaking;
  final bool isPaused;
  final int currentLineIndex;
  final int currentWordIndex;
  final int totalLines;
  final double speed;
  final double pitch;
  final String voice;
  final String language;
  final String currentText;
  final String novelTitle;
  final String novelAuthor;
  final TtsHighlightMode highlightMode;
  final Duration totalDuration;

  const TtsManagerState({
    this.isSpeaking = false,
    this.isPaused = false,
    this.currentLineIndex = 0,
    this.currentWordIndex = 0,
    this.totalLines = 0,
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

  TtsManagerState copyWith({
    bool? isSpeaking,
    bool? isPaused,
    int? currentLineIndex,
    int? currentWordIndex,
    int? totalLines,
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
      currentLineIndex: currentLineIndex ?? this.currentLineIndex,
      currentWordIndex: currentWordIndex ?? this.currentWordIndex,
      totalLines: totalLines ?? this.totalLines,
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
  List<String> _lines = [];
  int _currentLine = 0;
  List<int> _lineCharOffsets = []; // cumulative char offset of each line's start

  List<String> get lines => _lines;

  /// Returns a 0.0–1.0 fraction representing where [lineIndex] sits
  /// within the full chapter plain text, by actual character count.
  /// Much more accurate than lineIndex / totalLines for scroll purposes.
  double charOffsetRatioForLine(int lineIndex) {
    if (_lineCharOffsets.isEmpty || _lines.isEmpty) return 0.0;
    final totalChars = _lineCharOffsets.last + (_lines.last.length);
    if (totalChars <= 0) return 0.0;
    final clampedIndex = lineIndex.clamp(0, _lineCharOffsets.length - 1);
    return _lineCharOffsets[clampedIndex] / totalChars;
  }

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

    // Android notification
    TtsNotification.show(
      chapterName: currentText,
      currentLine: state.currentLineIndex + 1,
      totalLines: state.totalLines,
      isPaused: state.isPaused,
      novelTitle: novelTitle,
    );

    // MPRIS / media session — title = novel title, artist = author
    final position = state.totalLines > 0
        ? Duration(seconds: (state.totalDuration.inSeconds * state.currentLineIndex / state.totalLines).round())
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

  /// Extract plain text paragraphs and sentences from HTML for highlighting.
  /// Returns (paragraphs, sentences) where each is a list of trimmed text.
  static List<String> extractParagraphs(String html) {
    final text = html.replaceAll(RegExp(r'<[^>]*>'), '\n').replaceAll(RegExp(r'\s+'), ' ').trim();
    final paragraphs = <String>[];
    for (final p in text.split(RegExp(r'\n\s*\n|\n'))) {
      final trimmed = p.trim();
      if (trimmed.isNotEmpty) paragraphs.add(trimmed);
    }
    return paragraphs;
  }

  static List<String> extractSentences(String text) {
    final sentences = <String>[];
    for (final s in text.split(RegExp(r'(?<=[.!?])\s+'))) {
      if (s.trim().isNotEmpty) sentences.add(s.trim());
    }
    return sentences;
  }

  Future<void> startFromHtml(String html, {int startLine = 0, String? coverUrl, String? novelTitle, String? novelAuthor}) async {
    // Decode common typographic entities BEFORE stripping tags, so the resulting
    // plain text matches what _PlainMapping produces when the highlighter runs.
    // Without this, smart quotes like &ldquo; stay as "&ldquo;" in the TTS text
    // but appear as “ in the HTML mapping, causing sentence matching to fail.
    final decoded = html
        .replaceAll('&ldquo;', '\u201C').replaceAll('&rdquo;', '\u201D')
        .replaceAll('&lsquo;', '\u2018').replaceAll('&rsquo;', '\u2019')
        .replaceAll('&mdash;', '\u2014').replaceAll('&ndash;', '\u2013')
        .replaceAll('&hellip;', '\u2026').replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"').replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ').replaceAll('&#160;', ' ')
        // Normalize unicode typographic quotes/dashes to ASCII equivalents
        // so TTS reads them correctly and matching is consistent.
        .replaceAll('\u201C', '"').replaceAll('\u201D', '"')
        .replaceAll('\u2018', "'").replaceAll('\u2019', "'")
        .replaceAll('\u2014', ' - ').replaceAll('\u2013', '-')
        .replaceAll('\u2026', '...');
    final text = decoded.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    // Split into sentences — each sentence becomes one TTS line
    final lines = <String>[];
    for (var s in text.split(RegExp(r'(?<=[.!?])\s+'))) {
      final trimmed = s.trim();
      if (trimmed.isEmpty) continue;

      // If a sentence is very long (>300 chars), split further at commas/semicolons
      // to prevent TTS engine from choking on huge chunks
      if (trimmed.length > 300) {
        final subParts = trimmed.split(RegExp(r'(?<=[,;])\s+'));
        String buffer = '';
        for (final part in subParts) {
          if (buffer.length + part.length > 280) {
            if (buffer.isNotEmpty) lines.add(buffer.trim());
            buffer = part;
          } else {
            buffer = buffer.isEmpty ? part : '$buffer $part';
          }
        }
        if (buffer.isNotEmpty) lines.add(buffer.trim());
      } else {
        lines.add(trimmed);
      }
    }
    if (lines.isEmpty) return;

    _lines = lines;
    _currentLine = startLine;

    // Build cumulative character offset table for pixel-accurate scroll
    _lineCharOffsets = [];
    int offset = 0;
    for (final line in lines) {
      _lineCharOffsets.add(offset);
      offset += line.length + 1; // +1 for the space/newline between sentences
    }

    // Estimate total duration: ~15 chars/second at 1x speed, adjusted by speed setting
    final totalChars = lines.fold(0, (sum, l) => sum + l.length);
    final estimatedSeconds = (totalChars / 15.0 / state.speed).round();

    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      currentLineIndex: startLine,
      totalLines: lines.length,
      currentText: lines[startLine],
      novelTitle: novelTitle ?? '',
      novelAuthor: novelAuthor ?? '',
      totalDuration: Duration(seconds: estimatedSeconds),
    );

    // Speak ALL lines as one continuous audio (no gaps)
    final provider = _getProvider();
    await provider.init();

    // Set cover art for media controls (await download)
    if (coverUrl != null) {
      await TtsNotification.setCoverArt(coverUrl);
      await TtsMpris.setCoverArt(coverUrl);
      // Re-send notification/MPRIS with cover art after download
      _updateNotification();
    }

    _updateNotification();
    await provider.speakAll(
      lines.sublist(startLine),
      speed: state.speed,
      pitch: state.pitch,
      onLineStart: (lineIndex) {
        if (!state.isSpeaking || state.isPaused) return;
        final actualIndex = startLine + lineIndex;
        _currentLine = actualIndex;
        if (actualIndex < _lines.length) {
          state = state.copyWith(
            currentLineIndex: actualIndex,
            currentWordIndex: 0,
            currentText: _lines[actualIndex],
          );
          _updateNotification();
        }
      },
      onWordStart: (lineIndex, wordIndex) {
        if (!state.isSpeaking || state.isPaused) return;
        final actualIndex = startLine + lineIndex;
        if (actualIndex < _lines.length) {
          state = state.copyWith(
            currentLineIndex: actualIndex,
            currentText: _lines[actualIndex],
            currentWordIndex: wordIndex,
          );
        }
      },
    );
    // Finished
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
    state = state.copyWith(isSpeaking: false, isPaused: false, currentLineIndex: 0, currentText: '');
    _lines = [];
    _currentLine = 0;
    TtsNotification.hide();
  }

  Future<void> skipForward() async {
    if (_currentLine < _lines.length - 1) {
      await _getProvider().stop();
      _currentLine++;
      await _resumeFromLine(_currentLine);
    }
  }

  Future<void> skipBackward() async {
    if (_currentLine > 0) {
      await _getProvider().stop();
      _currentLine--;
      await _resumeFromLine(_currentLine);
    }
  }

  /// Resume TTS playback from a specific line index.
  Future<void> _resumeFromLine(int startLine) async {
    if (startLine < 0 || startLine >= _lines.length) return;

    final remaining = _lines.sublist(startLine);
    state = state.copyWith(
      isSpeaking: true,
      isPaused: false,
      currentLineIndex: startLine,
      currentText: _lines[startLine],
      currentWordIndex: 0,
    );
    _updateNotification();

    final provider = _getProvider();
    await provider.init();
    await provider.speakAll(
      remaining,
      speed: state.speed,
      pitch: state.pitch,
      onLineStart: (lineIndex) {
        final actualIndex = startLine + lineIndex;
        _currentLine = actualIndex;
        if (actualIndex < _lines.length) {
          state = state.copyWith(
            currentLineIndex: actualIndex,
            currentWordIndex: 0,
            currentText: _lines[actualIndex],
          );
          _updateNotification();
        }
      },
      onWordStart: (lineIndex, wordIndex) {
        state = state.copyWith(currentWordIndex: wordIndex);
      },
    );
    // Finished
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
