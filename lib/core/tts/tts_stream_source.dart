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

  /// Whether [bytes] carries a RIFF/WAVE container (device engines emit WAV,
  /// Edge emits MP3).
  bool get isWav =>
      _bytes.length >= 12 &&
      _bytes[0] == 0x52 && // R
      _bytes[1] == 0x49 && // I
      _bytes[2] == 0x46 && // F
      _bytes[3] == 0x46 && // F
      _bytes[8] == 0x57 && // W
      _bytes[9] == 0x41 && // A
      _bytes[10] == 0x56 && // V
      _bytes[11] == 0x45; // E

  /// MIME type matching the encoded payload. The platform decoder trusts
  /// this hint; feeding WAV data with an MP3 type makes ExoPlayer fail and
  /// treat the item as finished immediately.
  String get contentType => isWav ? 'audio/wav' : 'audio/mpeg';

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
    // just_audio/ExoPlayer legitimately issues range requests (media sniffing,
    // re-preparing the current item when the playlist changes, buffering
    // transitions). We hold the complete bytes in memory, so serving any
    // range is trivial — and REQUIRED: throwing here fails the platform-side
    // update without surfacing an error to the caller, which used to wedge
    // playlist appends forever (playback stalled at chunk 0).
    final from = (start ?? 0).clamp(0, _bytes.length);
    final to = (end ?? _bytes.length).clamp(from, _bytes.length);

    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: _bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream<Uint8List>.value(Uint8List.sublistView(_bytes, from, to)),
      contentType: contentType,
    );
  }
}
