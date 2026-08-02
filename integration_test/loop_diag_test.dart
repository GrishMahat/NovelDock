import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.mpvProperties = const {'network-timeout': '0'};
  JustAudioMediaKit.ensureInitialized(linux: true, windows: true);

  testWidgets('LoopMode.all keeps looping a concatenated playlist',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('loopdiag');
    final paths = <String>[
      '/tmp/opencode/t0.wav',
      '/tmp/opencode/t1.wav',
      '/tmp/opencode/t2.wav',
    ];
    for (final p in paths) {
      expect(File(p).existsSync(), isTrue, reason: p);
    }

    final player = AudioPlayer();
    addTearDown(() async {
      await player.dispose();
      dir.deleteSync(recursive: true);
    });

    final source = ConcatenatingAudioSource(
      children: [
        for (final p in paths) AudioSource.uri(Uri.file(p)),
      ],
    );
    await player.setAudioSource(source);
    await player.setLoopMode(LoopMode.all);
    player.play();

    final states = <String>[];
    final sub = player.playbackEventStream.listen((e) {
      states.add(
          'i=${e.currentIndex} s=${e.processingState.name} '
          'pos=${e.updatePosition.inMilliseconds}ms '
          'dur=${e.duration?.inMilliseconds ?? -1}ms');
    });
    final posSub = player.positionStream.listen((d) {
      debugPrint('DIAG pos i=${player.currentIndex} ${d.inMilliseconds}ms');
    });

    await Future<void>.delayed(const Duration(seconds: 12));
    await sub.cancel();
    await posSub.cancel();

    debugPrint('DIAG currentIndex=${player.currentIndex}');
    debugPrint('DIAG playing=${player.playing} '
        'state=${player.processingState.name} '
        'loopMode=${player.loopMode.name}');
    debugPrint('DIAG states tail:');
    for (final s in states.take(200)) {
      debugPrint('DIAG   $s');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
