import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'package:noveldock/core/tts/chunker.dart';
import 'package:noveldock/core/tts/controller.dart';
import 'package:noveldock/core/tts/engine/edge_tts_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);

  Future<void> runCase(
    String label,
    String voiceId,
    String locale,
    List<String> paragraphs,
  ) async {
    final controller = TtsPlaybackController(prefetchWindow: 4);
    final engine = EdgeTtsEngine();
    addTearDown(() async {
      await controller.stop();
      await engine.close();
    });

    final chunks = const TtsChunker().chunkParagraphs(paragraphs);
    debugPrint('[$label] chunks=${chunks.length}');

    final events = <String>[];
    controller.onChunkCompleted = (i) => events.add('done:$i');
    controller.onError = (e, {required bool fatal}) {
      events.add('error:$e');
      debugPrint('[$label] ERROR $e fatal=$fatal');
    };
    final completed = Completer<void>();
    controller.onCompleted = () {
      events.add('completed');
      if (!completed.isCompleted) completed.complete();
    };

    await controller.start(
      chunks: chunks,
      engine: engine,
      voiceId: voiceId,
      rate: '+0%',
      pitch: '+0Hz',
      locale: locale,
    );

    try {
      await completed.future.timeout(const Duration(minutes: 2));
    } catch (e) {
      debugPrint('[$label] TIMEOUT/FAIL: $e');
      events.add('timeout');
    }
    controller.onCompleted = null;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final dur = controller.player.audioPlayer.duration;
    final pos = controller.player.audioPlayer.position;
    final estimatedTotal = controller.totalDuration;
    final lastBoundaries =
        controller.chunks.isNotEmpty ? controller.boundariesForTest[controller.chunks.length - 1] : null;
    String? lastBoundaryEnd;
    if (lastBoundaries != null && lastBoundaries.isNotEmpty) {
      final last = lastBoundaries.last;
      lastBoundaryEnd =
          '${(last.offset + last.duration).inMilliseconds}ms (word "${last.word}", '
          'offset ${last.offset.inMilliseconds}ms dur ${last.duration.inMilliseconds}ms)';
    }
    debugPrint('[$label] events=$events');
    debugPrint('[$label] player: pos=${pos.inMilliseconds}ms '
        'dur=${dur?.inMilliseconds ?? -1}ms estTotal=${estimatedTotal.inMilliseconds}ms');
    debugPrint('[$label] lastBoundaryEnd=$lastBoundaryEnd');
    debugPrint('[$label] wordCount=${lastBoundaries?.length}');
    await controller.stop();
    await engine.close();
  }

  testWidgets('zh vs en boundary accuracy', (tester) async {
    await runCase(
      'en',
      'en-US-BrianMultilingualNeural',
      'en-US',
      [
        'The quick brown fox jumps over the lazy dog. '
            'He then rested under a large oak tree.',
        'The second paragraph begins here. It has two sentences.',
      ],
    );
    await runCase(
      'zh',
      'zh-CN-XiaoxiaoNeural',
      'zh-CN',
      [
        '清晨的阳光洒在古老的城墙上，空气中弥漫着淡淡的桂花香。'
            '老人在城门边摆了一个小小的茶摊。',
        '他每天都会在这里坐上整整一个上午。',
      ],
    );
  });
}
