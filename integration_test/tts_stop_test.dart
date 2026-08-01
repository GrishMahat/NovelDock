import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'package:noveldock/core/tts/chunker.dart';
import 'package:noveldock/core/tts/controller.dart';
import 'package:noveldock/core/tts/engine/edge_tts_engine.dart';
import 'package:noveldock/core/tts/engine/tts_engine.dart';

/// Yields cached MP3 bytes with a growing delay between chunks so stop() can
/// be exercised while the pipeline is idle at the prefetch bound.
class FakeGapEngine implements TtsEngine {
  final Uint8List mp3;
  final Duration gap;

  FakeGapEngine(this.mp3, this.gap);

  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake Gap';
  @override
  bool get supportsWordBoundaries => true;
  @override
  bool get requiresNetwork => false;

  @override
  Future<List<TtsEngineVoice>> getVoices() async => [];
  @override
  Future<void> init() async {}
  @override
  Future<void> close() async {}
  @override
  void reopen() {}

  @override
  Stream<TtsSynthesisEvent> synthesize(
    String text, {
    required String voiceId,
    required String rate,
    required String pitch,
    String? locale,
  }) async* {
    await Future<void>.delayed(gap);
    yield TtsAudioBytes(mp3);
    yield TtsTurnEnd();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.mpvProperties = const {'network-timeout': '0'};
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);

  testWidgets('stop() must halt playback promptly and stay halted',
      (tester) async {
    final real = EdgeTtsEngine();
    addTearDown(real.close);
    final bytes = <int>[];
    await for (final e in real.synthesize(
      'The quick brown fox jumps over the lazy dog.',
      voiceId: 'en-US-BrianMultilingualNeural',
      rate: '+0%',
      pitch: '+0Hz',
      locale: 'en-US',
    )) {
      if (e is TtsAudioBytes) bytes.addAll(e.bytes);
    }
    final mp3 = Uint8List.fromList(bytes);
    debugPrint('DIAG mp3 bytes=${mp3.length}');

    final chunks = <TtsChunk>[
      for (var i = 0; i < 6; i++)
        TtsChunk(
          index: i,
          paragraphIndex: 0,
          startOffset: 0,
          endOffset: 40,
          paragraphWordOffset: 0,
          sentenceCount: 1,
          estimatedDurationMs: 3000,
          text: 'synthetic chunk $i',
        ),
    ];

    final controller = TtsPlaybackController(
      prefetchWindow: 4,
      stallTimeout: const Duration(seconds: 6),
    );

    final events = <String>[];
    controller.onWord = (c, w) => events.add('word:$c:$w');
    controller.onChunkStart = (c) => events.add('start:$c');
    controller.onChunkCompleted = (c) => events.add('done:$c');
    controller.onError = (e, {required bool fatal}) =>
        events.add('error:$e');

    final engine = FakeGapEngine(mp3, const Duration(milliseconds: 200));
    await controller.start(
      chunks: chunks,
      engine: engine,
      voiceId: 'en-US-BrianMultilingualNeural',
      rate: '+0%',
      pitch: '+0Hz',
      locale: 'en-US',
    );

    // Let the first chunk actually play.
    await tester.pump(const Duration(seconds: 2));
    expect(controller.player.audioPlayer.playing, isTrue,
        reason: 'should be playing before stop');

    final startEventsBeforeStop = events.where((e) => e.startsWith('start:')).length;
    debugPrint('DIAG chunk start events before stop=$startEventsBeforeStop');
    expect(startEventsBeforeStop, greaterThan(0),
        reason: 'sanity: chunk start events should have fired while playing');

    final stopwatch = Stopwatch()..start();
    await controller.stop();
    stopwatch.stop();
    debugPrint('DIAG stop took ${stopwatch.elapsedMilliseconds}ms');
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)),
        reason: 'stop() must not block on the engine close handshake');

    expect(controller.player.audioPlayer.playing, isFalse,
        reason: 'playback must stop');
    final stoppedPosition = controller.position;

    // Give the pipeline time to (wrongly) resume if it ever would.
    await tester.pump(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(seconds: 1));

    expect(controller.player.audioPlayer.playing, isFalse,
        reason: 'playback must stay stopped');
    expect((controller.position - stoppedPosition).abs() <
        const Duration(milliseconds: 300), isTrue,
        reason: 'position must freeze after stop');

    final startEventsAfterStop = events.where((e) => e.startsWith('start:')).length;
    expect(startEventsAfterStop, startEventsBeforeStop,
        reason: 'no chunk start events may fire after stop');
    debugPrint('DIAG chunk start events after stop=$startEventsAfterStop');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
