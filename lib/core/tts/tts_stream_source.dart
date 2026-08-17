// StreamAudioSource is marked @experimental in just_audio but is the
// documented API for in-memory streaming; this is a deliberate use.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// A [StreamAudioSource] for one TTS chunk.
///
/// Each chunk is a complete MP3 byte sequence served as its own playlist item.
///
/// The source is intentionally non-seekable. The entire chunk is synthesized
/// before the source is attached to the player, so the player receives a
/// complete fixed-length stream.
class TtsStreamSource extends StreamAudioSource {
  final Uint8List _bytes;
  final int? contentLength;

  TtsStreamSource({required Uint8List bytes})
    : _bytes = bytes,
      contentLength = bytes.length,
      super(tag: 'tts-stream');

  bool get isClosed => true;

  /// Compatibility helper for the existing controller API.
  ///
  /// Bytes are accumulated before the source is created now, which avoids the
  /// lifetime problem of keeping a StreamController alive across multiple
  /// player requests.
  static TtsStreamSource fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError.value(
        bytes,
        'bytes',
        'TTS stream cannot contain empty audio',
      );
    }

    return TtsStreamSource(bytes: Uint8List.fromList(bytes));
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (start != null && start != 0) {
      throw StateError('TtsStreamSource does not support seeking');
    }

    if (end != null && end != _bytes.length) {
      throw StateError('TtsStreamSource does not support range requests');
    }

    return StreamAudioResponse(
      rangeRequestsSupported: false,
      sourceLength: _bytes.length,
      contentLength: _bytes.length,
      offset: null,
      stream: Stream<Uint8List>.value(_bytes),
      contentType: 'audio/mpeg',
    );
  }
}
