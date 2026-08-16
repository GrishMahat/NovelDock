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

/// Replays cached MP3 bytes with an artificial delay after the first chunk,
/// simulating real-world synthesis lag while earlier audio is still playing.
class FakeSlowEngine implements TtsEngine {
  final Uint8List mp3;
  final Duration delayAfterChunk0;

  FakeSlowEngine(this.mp3, this.delayAfterChunk0);

  int _turns = 0;

  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake Slow';
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
  void invalidateSession() {}

  @override
  Stream<TtsSynthesisEvent> synthesize(
    String text, {
    required String voiceId,
    required String rate,
    required String pitch,
    String? locale,
  }) async* {
    final turn = _turns++;
    if (turn > 0) {
      await Future<void>.delayed(delayAfterChunk0);
    }
    yield TtsAudioBytes(mp3);
    yield TtsTurnEnd();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.mpvProperties = const {'network-timeout': '0'};
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);

  testWidgets('slow synthesis must not stall or truncate playback',
      (tester) async {
    // Real ~3s of speech to replay.
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
      for (var i = 0; i < 3; i++)
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
    final engine = FakeSlowEngine(mp3, const Duration(seconds: 10));
    addTearDown(() async {
      await controller.stop();
    });

    final events = <String>[];
    controller.onChunkCompleted = (i) => events.add('done:$i');
    controller.onError = (e, {required bool fatal}) {
      events.add('error:$e');
      debugPrint('DIAG error $e fatal=$fatal');
    };
    final completed = Completer<void>();
    controller.onCompleted = () {
      events.add('completed');
      if (!completed.isCompleted) completed.complete();
    };

    await controller.start(
      chunks: chunks,
      engine: engine,
      voiceId: 'en-US-BrianMultilingualNeural',
      rate: '+0%',
      pitch: '+0Hz',
      locale: 'en-US',
    );

    // Poll player state to detect premature completion.
    final states = <String>[];
    final poll = Timer.periodic(const Duration(seconds: 1), (_) {
      final p = controller.player.audioPlayer;
      states.add(
          't=${(p.position.inMilliseconds ~/ 1000)}s '
          'state=${p.processingState.name} playing=${p.playing} '
          'pos=${p.position.inMilliseconds}ms dur=${p.duration?.inMilliseconds ?? -1}ms');
    });

    Duration? waited;
    try {
      await completed.future.timeout(const Duration(seconds: 90));
      waited = const Duration(seconds: 90);
    } catch (e) {
      debugPrint('DIAG TIMEOUT: $e');
      events.add('timeout');
    }
    poll.cancel();
    controller.onCompleted = null;

    debugPrint('DIAG events=$events');
    debugPrint('DIAG states:');
    for (final s in states) {
      debugPrint('DIAG   $s');
    }
    debugPrint('DIAG waited=${waited?.inSeconds}s');

    expect(events, containsAll(['done:0', 'done:1', 'done:2', 'completed']),
        reason: events.toString());
    expect(events.indexOf('done:2') < events.indexOf('completed'), isTrue,
        reason: events.toString());
    expect(events, isNot(contains('timeout')), reason: events.toString());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
