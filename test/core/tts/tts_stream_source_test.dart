import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/tts/tts_stream_source.dart';

Uint8List _wavBytes() {
  final bytes = BytesBuilder();

  bytes.add('RIFF'.codeUnits);
  bytes.add(Uint8List(4)); // placeholder size
  bytes.add('WAVE'.codeUnits);
  bytes.add('fmt '.codeUnits);
  bytes.add(Uint8List(20));

  return bytes.toBytes();
}

Uint8List _mp3Bytes() {
  final bytes = BytesBuilder();

  // ID3 header.
  bytes.add('ID3'.codeUnits);
  bytes.add(Uint8List(7));
  // MPEG frame sync.
  bytes.add([0xFF, 0xFB, 0x90, 0x00]);

  return bytes.toBytes();
}

void main() {
  group('TtsStreamSource', () {
    test('WAV payloads report audio/wav', () async {
      final source = TtsStreamSource.fromBytes(_wavBytes());

      expect(source.isWav, isTrue);
      expect(source.contentType, 'audio/wav');

      final response = await source.request();

      expect(response.contentType, 'audio/wav');
    });

    test('MP3 payloads report audio/mpeg', () async {
      final source = TtsStreamSource.fromBytes(_mp3Bytes());

      expect(source.isWav, isFalse);
      expect(source.contentType, 'audio/mpeg');

      final response = await source.request();

      expect(response.contentType, 'audio/mpeg');
    });

    test('payload length is exposed for range-free playback', () async {
      final bytes = _mp3Bytes();
      final source = TtsStreamSource.fromBytes(bytes);

      expect(source.contentLength, bytes.length);

      final response = await source.request();

      expect(response.contentLength, bytes.length);
      expect(
        await response.stream.fold<int>(0, (sum, chunk) => sum + chunk.length),
        bytes.length,
      );
    });

    test('empty bytes are rejected', () {
      expect(
        () => TtsStreamSource.fromBytes(Uint8List(0)),
        throwsArgumentError,
      );
    });

    test('range requests are served instead of throwing', () async {
      final bytes = _mp3Bytes();
      final source = TtsStreamSource.fromBytes(bytes);

      // ExoPlayer issues these while sniffing and re-preparing the current
      // item when the playlist changes. Throwing here used to wedge
      // playlist appends forever.
      final midResponse = await source.request(1, 4);

      expect(midResponse.rangeRequestsSupported, isTrue);
      expect(midResponse.sourceLength, bytes.length);
      expect(midResponse.offset, 1);
      expect(midResponse.contentLength, 3);
      expect(
        await midResponse.stream.fold<List<int>>(
          [],
          (acc, chunk) => acc..addAll(chunk),
        ),
        bytes.sublist(1, 4),
      );
    });

    test(
      'open-ended and clamped requests behave like a full response',
      () async {
        final bytes = _mp3Bytes();
        final source = TtsStreamSource.fromBytes(bytes);

        for (final request in [
          () => source.request(),
          () => source.request(0, null),
          () => source.request(0, bytes.length),
          () => source.request(null, null),
        ]) {
          final response = await request();

          expect(response.offset, 0);
          expect(response.contentLength, bytes.length);
          expect(
            await response.stream.fold<int>(
              0,
              (sum, chunk) => sum + chunk.length,
            ),
            bytes.length,
          );
        }
      },
    );

    test('out-of-bounds ranges are clamped, not thrown', () async {
      final bytes = _mp3Bytes();
      final source = TtsStreamSource.fromBytes(bytes);

      final response = await source.request(bytes.length, bytes.length + 100);

      expect(response.contentLength, 0);
    });
  });
}
