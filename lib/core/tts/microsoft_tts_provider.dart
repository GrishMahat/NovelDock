import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';

const _tag = 'EdgeTTS';

class EdgeTtsVoice {
  final String id;
  final String name;
  final String language;
  final String? gender;

  const EdgeTtsVoice({required this.id, required this.name, required this.language, this.gender});
}

/// Timing info for one word within a synthesized chunk.
class WordTiming {
  final String text;
  final Duration offset;
  final Duration duration;

  const WordTiming({required this.text, required this.offset, required this.duration});

  Duration get end => offset + duration;
}

/// Result of synthesizing one chunk: audio bytes + word timings + duration.
class _SynthResult {
  final int lineIndex;
  final Uint8List audioBytes;
  final List<WordTiming> wordTimings;
  final Duration duration;

  const _SynthResult({
    required this.lineIndex,
    required this.audioBytes,
    required this.wordTimings,
    required this.duration,
  });
}

/// TTS provider using Microsoft Edge's Read Aloud API via flutter_edge_tts.
///
/// Architecture (streaming, inspired by the Chrome edge-tts-extension):
/// - Text is split into sentence-level chunks by the caller
/// - Each chunk is synthesized and played one at a time (streaming)
/// - Audio starts in ~3s instead of waiting for all chunks to synthesize
/// - Word boundary timings are tracked per-chunk via player.position
class MicrosoftTtsProvider {
  String _currentVoice = 'en-US-BrianMultilingualNeural';
  String? _tempDir;
  bool _speaking = false;
  bool _paused = false;
  Player? _player;
  bool _stopRequested = false;

  bool get isSpeaking => _speaking;
  bool get isPaused => _paused;

  Future<void> init() async {
    if (_tempDir != null) return;
    final dir = await getTemporaryDirectory();
    _tempDir = dir.path;
  }

  Future<void> dispose() async {
    await stop();
  }

  /// Synthesize one text chunk, returning audio bytes + word timings.
  Future<_SynthResult> _synthesizeChunk(String text, int index, double speed, double pitch) async {
    await init();

    final tts = FlutterEdgeTts(
      voice: _currentVoice,
      outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
      enableWordBoundary: true,
      enableSentenceBoundary: false,
    );

    final ratePercent = ((speed - 1.0) * 100).round();
    final rateStr = ratePercent >= 0 ? '+$ratePercent%' : '$ratePercent%';
    final pitchPercent = ((pitch - 1.0) * 50).round();
    final pitchStr = pitchPercent >= 0 ? '+$pitchPercent%' : '$pitchPercent%';

    final audioChunks = <Uint8List>[];
    final wordTimings = <WordTiming>[];
    Duration totalDuration = Duration.zero;

    final stream = tts.synthesizeStream(
      text,
      prosody: EdgeTtsProsody(rate: rateStr, pitch: pitchStr, volume: '100'),
    );

    await for (final event in stream) {
      if (event is EdgeTtsAudioChunkEvent) {
        audioChunks.add(event.chunk);
      } else if (event is EdgeTtsMetadataEvent) {
        for (final item in event.metadata.items) {
          if (item.type == 'WordBoundary') {
            final offsetMs = item.data.offset ~/ 10000;
            final durationMs = item.data.duration ~/ 10000;
            final txt = item.data.text?.text ?? '';
            wordTimings.add(WordTiming(
              text: txt,
              offset: Duration(milliseconds: offsetMs),
              duration: Duration(milliseconds: durationMs),
            ));
            totalDuration = Duration(milliseconds: offsetMs + durationMs);
          }
        }
      }
    }

    final builder = BytesBuilder();
    for (final chunk in audioChunks) {
      builder.add(chunk);
    }

    Log.d(_tag, 'Synthesized chunk $index: ${wordTimings.length} words, ${totalDuration.inMilliseconds}ms');

    return _SynthResult(
      lineIndex: index,
      audioBytes: builder.toBytes(),
      wordTimings: wordTimings,
      duration: totalDuration,
    );
  }

  /// Maximum number of chunks to synthesize ahead in the background.
  static const _lookAheadCount = 10;

  /// Speak multiple text chunks with look-ahead synthesis and streaming playback.
  Future<void> speakAll(
    List<String> lines, {
    double speed = 1.0,
    double pitch = 1.0,
    void Function(int lineIndex)? onLineStart,
    void Function(int lineIndex, int wordIndex)? onWordStart,
  }) async {
    if (lines.isEmpty) return;

    _stopRequested = false;
    _speaking = true;
    _paused = false;

    await init();
    Log.i(_tag, 'TTS temp dir: $_tempDir');

    final buffer = <int, _SynthResult>{};
    final synthesizing = <int>{};

    void fillBuffer(int start, int end) {
      for (int j = start; j < end && j < lines.length; j++) {
        if (synthesizing.contains(j) || buffer.containsKey(j)) continue;
        synthesizing.add(j);
        final idx = j;
        _synthesizeChunk(lines[idx], idx, speed, pitch).then((result) {
          if (!_stopRequested) buffer[idx] = result;
        }).catchError((e) {
          Log.e(_tag, 'Background synthesis failed for chunk $idx', e);
        });
      }
    }

    fillBuffer(1, _lookAheadCount);

    for (int i = 0; i < lines.length && !_stopRequested; i++) {
      _SynthResult? result = buffer.remove(i);
      if (result == null) {
        Log.d(_tag, 'Chunk $i not in buffer, synthesizing on demand');
        try {
          result = await _synthesizeChunk(lines[i], i, speed, pitch);
        } catch (e) {
          Log.e(_tag, 'Synthesis failed for chunk $i', e);
          continue;
        }
      }

      if (_stopRequested) break;

      fillBuffer(i + 1, i + 1 + _lookAheadCount);

      final audioPath = p.join(_tempDir!, 'tts_chunk_$i.mp3');
      await File(audioPath).writeAsBytes(result.audioBytes);
      Log.i(_tag, 'Wrote audio file: $audioPath (${result.audioBytes.length} bytes)');

      onLineStart?.call(i);

      await _playChunkAndWait(audioPath, result, onWordStart);
    }

    _speaking = false;
    _cleanupTempFiles();
  }

  /// Play a single chunk's audio file and track word position via player position.
  Future<void> _playChunkAndWait(
    String audioPath,
    _SynthResult result,
    void Function(int lineIndex, int wordIndex)? onWordStart,
  ) async {
    final player = Player();
    _player = player;
    try {
      Log.i(_tag, 'Opening media: $audioPath');
      await player.open(Media('file://$audioPath'));
      Log.i(_tag, 'Media opened, starting playback');

      final completer = Completer<void>();
      final sub = player.stream.completed.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });

      await player.play();
      Log.i(_tag, 'Playback started');

      int lastWordIndex = -1;

      while (!completer.isCompleted && !_stopRequested) {
        if (_paused) {
          await Future.delayed(const Duration(milliseconds: 50));
          continue;
        }

        await Future.delayed(const Duration(milliseconds: 50));

        final elapsed = player.state.position;
        int currentWord = -1;
        for (int wi = result.wordTimings.length - 1; wi >= 0; wi--) {
          if (elapsed >= result.wordTimings[wi].offset) {
            currentWord = wi;
            break;
          }
        }

        if (currentWord != -1 && currentWord != lastWordIndex) {
          lastWordIndex = currentWord;
          onWordStart?.call(result.lineIndex, currentWord);
        }
      }

      await sub.cancel();
      Log.i(_tag, 'Chunk playback completed');
    } catch (e) {
      Log.e(_tag, 'Chunk playback failed: $e');
    } finally {
      if (_player == player) _player = null;
      try {
        await player.dispose();
      } catch (_) {}
    }
  }

  void _cleanupTempFiles() {
    try {
      final dir = Directory(_tempDir!);
      if (dir.existsSync()) {
        for (final f in dir.listSync()) {
          if (f is File && p.basename(f.path).startsWith('tts_')) {
            try { f.deleteSync(); } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _stopPlayback() async {
    _stopRequested = true;
    final player = _player;
    if (player != null) {
      try { await player.stop(); } catch (_) {}
      try { await player.dispose(); } catch (_) {}
      _player = null;
    }
    _speaking = false;
    _paused = false;
  }

  Future<void> pause() async {
    final player = _player;
    if (player != null) {
      try {
        await player.pause();
        _paused = true;
      } catch (_) {}
    }
  }

  Future<void> resume() async {
    final player = _player;
    if (player != null) {
      try {
        await player.play();
        _paused = false;
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _stopPlayback();
    _cleanupTempFiles();
  }

  /// Single text speak (for voice samples).
  Future<void> speak(String text, {double speed = 1.0, double pitch = 1.0}) async {
    await init();
    try {
      await _stopPlayback();
      final audioPath = p.join(_tempDir!, 'tts_sample.mp3');

      final tts = FlutterEdgeTts(
        voice: _currentVoice,
        outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
      );

      final ratePercent = ((speed - 1.0) * 100).round();
      final rateStr = ratePercent >= 0 ? '+$ratePercent%' : '$ratePercent%';
      final pitchPercent = ((pitch - 1.0) * 50).round();
      final pitchStr = pitchPercent >= 0 ? '+$pitchPercent%' : '$pitchPercent%';

      await tts.synthesizeToFile(
        text,
        audioFilePath: audioPath,
        metadataFilePath: '$audioPath.json',
        prosody: EdgeTtsProsody(rate: rateStr, pitch: pitchStr, volume: '100'),
      );

      final file = File(audioPath);
      for (int i = 0; i < 30; i++) {
        if (await file.exists() && await file.length() > 0) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      _speaking = true;
      _paused = false;

      final player = Player();
      _player = player;
      await player.open(Media('file://$audioPath'));
      final completer = Completer<void>();
      player.stream.completed.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });
      await player.play();
      await completer.future;
      if (_player == player) _player = null;
      try {
        await player.dispose();
      } catch (_) {}


      _speaking = false;
    } catch (e) {
      Log.e(_tag, 'Failed to speak', e);
      _speaking = false;
    }
  }

  Future<List<EdgeTtsVoice>> getVoices() async {
    final tts = FlutterEdgeTts(
      voice: _currentVoice,
      outputFormat: EdgeTtsOutputFormat.audio24Khz96KbitrateMonoMp3,
    );
    try {
      final voices = await tts.getVoices();
      return voices.map((v) => EdgeTtsVoice(
        id: v.shortName,
        name: '${v.shortName} (${v.gender})',
        language: v.locale,
        gender: v.gender,
      )).toList();
    } catch (e) {
      Log.e(_tag, 'Failed to get voices', e);
      return [];
    }
  }

  Future<void> setVoice(String voiceId) async {
    _currentVoice = voiceId;
  }

  Future<void> setLanguage(String language) async {
    // Only change the language — don't override the user's voice selection.
  }
}
