import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';

import 'package:noveldock/core/tts/engine/edge_tts_engine.dart';
import 'package:noveldock/core/tts/engine/tts_engine.dart';

// Live-network test against the real Edge TTS endpoint — it is what catches
// service-side breakage like the Sec-MS-GEC v2 403s. Too slow/flaky for the
// normal suite, so run it explicitly:
//   EDGE_TTS_LIVE=1 flutter test test/core/tts/edge_tts_engine_test.dart
void main() {
  test(
    'EdgeTtsEngine live: voices + short turn + long turn',
    () async {
      final engine = EdgeTtsEngine();

      final voices = await engine.getVoices();
      expect(voices, isNotEmpty);
      final voice = voices.firstWhere(
        (v) => v.id == 'en-US-BrianMultilingualNeural',
        orElse: () => voices.first,
      );

      Future<(int, int, bool, String?)> run(String text) async {
        final bytes = <int>[];
        final boundaries = <TtsWordBoundary>[];
        var turnEnd = false;
        String? error;
        await for (final event in engine.synthesize(
          text,
          voiceId: voice.id,
          locale: voice.locale,
          rate: '+0%',
          pitch: '+0Hz',
        )) {
          switch (event) {
            case TtsAudioBytes():
              bytes.addAll(event.bytes);
            case TtsWordBoundary():
              boundaries.add(event);
            case TtsTurnEnd():
              turnEnd = true;
            case TtsSynthesisError():
              error = '$event';
          }
        }
        return (bytes.length, boundaries.length, turnEnd, error);
      }

      final short = await run('Hello from the new engine.');
      expect(short.$3, isTrue, reason: 'short: $short');
      expect(short.$4, isNull);
      expect(short.$1, greaterThan(500));
      expect(short.$2, greaterThan(2));

      final longText = 'The quick brown fox jumps over the lazy dog. ' * 100;
      final long = await run(longText);
      expect(long.$3, isTrue, reason: 'long: $long');
      expect(long.$4, isNull);
      expect(long.$1, greaterThan(short.$1));
      expect(long.$2, greaterThan(800));

      await engine.close();
    },
    skip: Platform.environment['EDGE_TTS_LIVE'] == null
        ? 'live network test; set EDGE_TTS_LIVE=1 to run'
        : null,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
