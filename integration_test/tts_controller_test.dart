import 'dart:async';

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

  testWidgets(
    'TTS pipeline plays three chunks end to end with word events',
    (tester) async {
      final controller = TtsPlaybackController(prefetchWindow: 2);
      final engine = EdgeTtsEngine();
      addTearDown(() async {
        await controller.stop();
        await engine.close();
      });

      final chunks = const TtsChunker().chunkParagraphs([
        'The quick brown fox jumps over the lazy dog. '
            'He then rested under a large oak tree.',
        'The second paragraph begins here. It has two sentences.',
        'This is the third paragraph, added to check that playback '
            'continues past the old stopping point. '
            'It must play all the way to this final sentence.',
      ]);
      expect(chunks.length, greaterThanOrEqualTo(3));

      final events = <String>[];
      controller.onChunkStart = (i) {
        events.add('start:$i');
        debugPrint('LIVE start:$i');
      };
      controller.onWord = (i, w) {
        events.add('word:$i:$w');
        if (w % 3 == 0) debugPrint('LIVE word:$i:$w');
      };
      controller.onChunkCompleted = (i) {
        events.add('done:$i');
        debugPrint('LIVE done:$i');
      };
      controller.onError = (e, {required bool fatal}) {
        events.add('error:$e');
        debugPrint('LIVE error:$e fatal:$fatal');
      };

      await controller.start(
        chunks: chunks,
        engine: engine,
        voiceId: 'en-US-BrianMultilingualNeural',
        rate: '+0%',
        pitch: '+0Hz',
        locale: 'en-US',
      );

      final completed = Completer<void>();
      controller.onCompleted = () {
        events.add('completed');
        if (!completed.isCompleted) completed.complete();
      };

      await completed.future.timeout(const Duration(minutes: 2));
      controller.onCompleted = null;

      expect(events, contains('start:0'));
      expect(events, contains('done:0'));
      expect(events, contains('start:1'));
      expect(events, contains('done:1'));
      expect(events, contains('start:2'));
      expect(events, contains('done:2'));
      expect(
        events.where((e) => e.startsWith('word:0:')).length,
        greaterThan(1),
        reason: events.toString(),
      );
      expect(
        events.where((e) => e.startsWith('word:1:')).length,
        greaterThan(1),
        reason: events.toString(),
      );
      expect(
        events.where((e) => e.startsWith('word:2:')).length,
        greaterThan(1),
        reason: events.toString(),
      );
      // Every chunk must actually finish playing before the session ends:
      // the completion loop must never advance past a chunk whose audio has
      // not been delivered (regression: tail-propagated cumulative ends).
      expect(events.last, 'completed', reason: events.toString());
      expect(
        events.indexOf('done:2') < events.indexOf('completed'),
        isTrue,
        reason: events.toString(),
      );
      expect(events, isNot(contains('error:')), reason: events.toString());
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
