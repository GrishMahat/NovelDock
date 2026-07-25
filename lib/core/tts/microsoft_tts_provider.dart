import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_edge_tts/flutter_edge_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';

const _tag = 'EdgeTTS';
const _bufferSize = 15;

class EdgeTtsVoice {
  final String id;
  final String name;
  final String language;
  final String? gender;

  const EdgeTtsVoice({required this.id, required this.name, required this.language, this.gender});
}

/// Timing info for one word within a synthesized line.
class WordTiming {
  final String text;
  final Duration offset;
  final Duration duration;

  const WordTiming({required this.text, required this.offset, required this.duration});

  Duration get end => offset + duration;
}

/// Per-line timing data: audio file path + word timings.
class SynthesizedLine {
  final int lineIndex;
  final String audioPath;
  final List<WordTiming> wordTimings;
  final Duration totalDuration;

  const SynthesizedLine({
    required this.lineIndex,
    required this.audioPath,
    required this.wordTimings,
    required this.totalDuration,
  });
}

class MicrosoftTtsProvider {
  String _currentVoice = 'en-US-BrianMultilingualNeural';
  String? _tempDir;
  bool _speaking = false;
  bool _paused = false;
  Process? _playProcess;
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

  /// Synthesize one line, returning audio file path + word timings.
  Future<SynthesizedLine> _synthesizeLine(String text, int index, double speed, double pitch) async {
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
            final offsetMs = item.data.offset ~/ 10000; // Convert from 100ns to ms
            final durationMs = item.data.duration ~/ 10000;
            final text = item.data.text?.text ?? '';
            wordTimings.add(WordTiming(
              text: text,
              offset: Duration(milliseconds: offsetMs),
              duration: Duration(milliseconds: durationMs),
            ));
            totalDuration = Duration(milliseconds: offsetMs + durationMs);
          }
        }
      }
    }

    // Write audio to file
    final audioPath = p.join(_tempDir!, 'tts_${index}.mp3');
    final file = File(audioPath);
    final allBytes = BytesBuilder();
    for (final chunk in audioChunks) {
      allBytes.add(chunk);
    }
    await file.writeAsBytes(allBytes.toBytes());

    Log.d(_tag, 'Synthesized line $index: ${wordTimings.length} words, ${totalDuration.inMilliseconds}ms');

    return SynthesizedLine(
      lineIndex: index,
      audioPath: audioPath,
      wordTimings: wordTimings,
      totalDuration: totalDuration,
    );
  }

  /// Speak multiple lines with pre-buffering and word-level timing.
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

    // Queue of synthesized lines (with timing data)
    final audioQueue = Queue<SynthesizedLine>();
    final completer = Completer<void>();

    // Background synthesis task
    synthesisTask() async {
      int nextToSynth = 0;
      while (nextToSynth < lines.length && !_stopRequested) {
        while (audioQueue.length >= _bufferSize && !_stopRequested) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (_stopRequested) break;

        try {
          final synthesized = await _synthesizeLine(lines[nextToSynth], nextToSynth, speed, pitch);
          audioQueue.add(synthesized);
        } catch (e) {
          Log.e(_tag, 'Synthesis failed for line $nextToSynth', e);
          // Push dummy item to maintain 1-to-1 queue mapping
          audioQueue.add(SynthesizedLine(
            lineIndex: nextToSynth,
            audioPath: '',
            wordTimings: const [],
            totalDuration: Duration.zero,
          ));
        }
        nextToSynth++;
      }
    }

    final synthFuture = synthesisTask();

    // Playback loop
    playbackTask() async {
      for (int i = 0; i < lines.length && !_stopRequested; i++) {
        while (audioQueue.isEmpty && !_stopRequested) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        if (_stopRequested || audioQueue.isEmpty) break;

        final synthesized = audioQueue.removeFirst();
        onLineStart?.call(synthesized.lineIndex);

        if (synthesized.audioPath.isEmpty) continue; // Skip failed lines safely

        // Wait for file
        final file = File(synthesized.audioPath);
        for (int w = 0; w < 30 && !_stopRequested; w++) {
          if (await file.exists() && await file.length() > 0) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (_stopRequested) break;

        // Play and track word position
        await _playFileTracked(synthesized, onWordStart, synthesized.lineIndex);

        try { await file.delete(); } catch (_) {}
      }

      _speaking = false;
      if (!completer.isCompleted) completer.complete();
    }

    playbackTask();
    await synthFuture;
    await completer.future;
    _cleanupTempFiles();
  }

  /// Play a synthesized line and call onWordStart as each word begins.
  Future<void> _playFileTracked(
    SynthesizedLine line,
    void Function(int lineIndex, int wordIndex)? onWordStart,
    int lineIndex,
  ) async {
    if (line.audioPath.isEmpty) return;
    if (line.wordTimings.isEmpty) {
      // No timing data — just play
      await _playFile(line.audioPath);
      return;
    }

    Process? proc;
    try {
      if (Platform.isLinux) {
        proc = await Process.start('mpv', [
          '--no-video', '--no-terminal', '--really-quiet', line.audioPath,
        ]);
      } else if (Platform.isMacOS) {
        proc = await Process.start('afplay', [line.audioPath]);
      } else if (Platform.isWindows) {
        proc = await Process.start('powershell', [
          '-Command', '(New-Object Media.SoundPlayer "${line.audioPath}").PlaySync()',
        ]);
      }
      _playProcess = proc;

      if (proc != null) {
        final stopwatch = Stopwatch()..start();
        int lastWordIndex = -1;

        while (_playProcess != null && !_stopRequested) {
          if (_paused) {
            if (stopwatch.isRunning) stopwatch.stop();
            await Future.delayed(const Duration(milliseconds: 50));
            continue;
          }
          if (!stopwatch.isRunning) stopwatch.start();

          final exitCode = await proc.exitCode.timeout(
            const Duration(milliseconds: 50),
            onTimeout: () => -1,
          );
          if (exitCode != -1) break;

          final elapsed = stopwatch.elapsed;
          int currentWord = -1;
          for (int wi = line.wordTimings.length - 1; wi >= 0; wi--) {
            if (elapsed >= line.wordTimings[wi].offset) {
              currentWord = wi;
              break;
            }
          }

          if (currentWord != -1 && currentWord != lastWordIndex) {
            lastWordIndex = currentWord;
            onWordStart?.call(lineIndex, currentWord);
          }
        }
        stopwatch.stop();
      } else {
        await _playFile(line.audioPath);
      }
    } on ProcessException catch (e) {
      final tool = Platform.isLinux ? 'mpv' : Platform.isMacOS ? 'afplay' : 'PowerShell';
      Log.e(_tag, '$tool not found. Please install $tool to use TTS. Error: $e');
      await _playFile(line.audioPath);
    } catch (e) {
      Log.e(_tag, 'Tracked playback failed: $e');
      await _playFile(line.audioPath);
    }
  }

  Future<void> _playFile(String path) async {
    try {
      if (Platform.isLinux) {
        _playProcess = await Process.start('mpv', [
          '--no-video', '--no-terminal', '--really-quiet', path,
        ]);
        await _playProcess!.exitCode;
      } else if (Platform.isMacOS) {
        _playProcess = await Process.start('afplay', [path]);
        await _playProcess!.exitCode;
      } else if (Platform.isWindows) {
        _playProcess = await Process.start('powershell', [
          '-Command', '(New-Object Media.SoundPlayer "$path").PlaySync()',
        ]);
        await _playProcess!.exitCode;
      } else {
        Log.w(_tag, 'Audio playback not supported on this platform');
      }
    } on ProcessException catch (e) {
      final tool = Platform.isLinux ? 'mpv' : Platform.isMacOS ? 'afplay' : 'PowerShell';
      Log.e(_tag, '$tool not found. Please install $tool to use TTS. Error: $e');
    } catch (e) {
      Log.e(_tag, 'Playback failed: $e');
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
    if (_playProcess != null) {
      try { _playProcess!.kill(ProcessSignal.sigterm); } catch (_) {}
      _playProcess = null;
    }
    _speaking = false;
    _paused = false;
  }

  Future<void> pause() async {
    if (_playProcess != null) {
      try {
        // SIGSTOP/SIGCONT work on Linux and macOS (POSIX signals)
        _playProcess!.kill(ProcessSignal.sigstop);
        _paused = true;
      } catch (_) {}
    }
  }

  Future<void> resume() async {
    if (_playProcess != null) {
      try {
        _playProcess!.kill(ProcessSignal.sigcont);
        _paused = false;
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _stopPlayback();
    _cleanupTempFiles();
  }

  /// Single text speak (for voice samples)
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
        metadataFilePath: '${audioPath}.json',
        prosody: EdgeTtsProsody(rate: rateStr, pitch: pitchStr, volume: '100'),
      );

      final file = File(audioPath);
      for (int i = 0; i < 30; i++) {
        if (await file.exists() && await file.length() > 0) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      _speaking = true;
      _paused = false;
      await _playFile(audioPath);
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
    // If the current voice doesn't match the new language, the Edge TTS API
    // will still use the specified voice (it supports cross-language synthesis).
    // The user can manually pick a voice for the new language if desired.
  }
}
