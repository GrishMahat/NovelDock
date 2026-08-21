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

/// Yields cached MP3 bytes immediately for every turn (no boundaries, no
/// delay) so turns always complete and the pipeline goes idle quickly.
class FakeFastEngine implements TtsEngine {
  final Uint8List mp3;

  FakeFastEngine(this.mp3);

  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake Fast';
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
    yield TtsAudioBytes(mp3);
    yield TtsTurnEnd();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.mpvProperties = const {'network-timeout': '0'};
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);

  testWidgets('repeated stalls at the same chunk escalate to a bounded fatal', (
    tester,
  ) async {
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

    // Chunk 0 is estimated to last 20s but its real audio is only ~3s, so
    // the player drains it and freezes far before the estimated end. With a
    // prefetch window of 1 the pipeline blocks on the look-ahead gate waiting
    // for the playhead to advance past chunk 0 (which never happens) while
    // the stream source stays open: no new bytes, no position progress, and
    // not synthesizing, so the stall gate fires repeatedly at chunk 0.
    final chunks = <TtsChunk>[
      TtsChunk(
        index: 0,
        paragraphIndex: 0,
        startOffset: 0,
        endOffset: 40,
        paragraphWordOffset: 0,
        sentenceCount: 1,
        estimatedDurationMs: 20000,
        text: 'stuck chunk',
      ),
      for (var i = 1; i < 3; i++)
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
      prefetchWindow: 1,
      stallTimeout: const Duration(seconds: 3),
      maxStallRestarts: 3,
    );
    addTearDown(() async {
      await controller.stop();
    });
    final engine = FakeFastEngine(mp3);
    addTearDown(() async {
      await engine.close();
    });

    final events = <String>[];
    controller.onError = (e, {required bool fatal}) {
      events.add(fatal ? 'error:fatal:$e' : 'error:$e');
      debugPrint('DIAG error fatal=$fatal $e');
    };
    final fatal = Completer<void>();
    controller.onCompleted = () => events.add('completed');

    await controller.start(
      chunks: chunks,
      engine: engine,
      voiceId: 'en-US-BrianMultilingualNeural',
      rate: '+0%',
      pitch: '+0Hz',
      locale: 'en-US',
    );

    final poll = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final p = controller.player.audioPlayer;
      debugPrint(
        'DIAG t=${p.position.inMilliseconds}ms '
        'state=${p.processingState.name} playing=${p.playing} '
        'isRunning=${controller.isRunning} errors=${events.length}',
      );
      if (events.any((e) => e.startsWith('error:fatal'))) {
        if (!fatal.isCompleted) fatal.complete();
      }
    });

    try {
      await fatal.future.timeout(const Duration(seconds: 90));
    } catch (e) {
      debugPrint('DIAG TIMEOUT: $e');
    }
    poll.cancel();
    await Future<void>.delayed(const Duration(seconds: 2));

    debugPrint('DIAG final events=$events');
    debugPrint('DIAG final isRunning=${controller.isRunning}');

    // Bounded recovery: exactly one warm + one cold restart, then give up.
    final nonFatal = events
        .where((e) => e.startsWith('error:') && !e.startsWith('error:fatal'))
        .length;
    expect(nonFatal, 2, reason: events.toString());
    expect(
      events.where((e) => e.startsWith('error:fatal')).length,
      1,
      reason: events.toString(),
    );
    expect(controller.isRunning, isFalse, reason: events.toString());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
