// StreamAudioSource is marked @experimental in just_audio but is the
// documented API for in-memory streaming; this is a deliberate use.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// A [StreamAudioSource] for one TTS chunk.
///
/// Each chunk is a complete MP3 byte-sequence served as its own playlist
/// item, so mpv treats it as a discrete media entry (clean EOF, native
/// playlist looping). When the chunk's bytes are fully fed and the stream is
/// closed before mpv connects, [contentLength] is known and mpv sees a
/// fixed-length response instead of a chunked dynamic stream.
///
/// [contentLength] must stay `null` while the stream is still being fed:
/// fixed lengths break dynamic streams ("Content size exceeds specified
/// contentLength").
class TtsStreamSource extends StreamAudioSource {
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>();
  final int? contentLength;
  bool _closed = false;

  TtsStreamSource({this.contentLength}) : super(tag: 'tts-stream');

  bool get isClosed => _closed;

  void addBytes(Uint8List bytes) {
    if (bytes.isEmpty || _closed) return;
    _controller.add(bytes);
  }

  Future<void> closeStream() async {
    if (_closed) return;
    _closed = true;
    // Do NOT await close(): the future only completes once the `done` event
    // is delivered to a listener, and the player's proxy does not subscribe
    // until setPlaylist/addToPlaylist requests the stream — awaiting here
    // would hang the pipeline before playback ever starts. close() marks the
    // controller closed synchronously; the buffered bytes and `done` are
    // delivered when the player connects.
    unawaited(_controller.close());
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    if (start != null && start != 0) {
      throw StateError('TtsStreamSource does not support seeking');
    }
    // `offset` must stay null even for `Range: bytes=0-` requests: a non-null
    // offset makes just_audio take the range-response branch, which requires
    // `contentLength` and crashes when it is null (unknown-length stream).
    return StreamAudioResponse(
      rangeRequestsSupported: false,
      sourceLength: null,
      contentLength: contentLength,
      offset: null,
      stream: _controller.stream,
      contentType: 'audio/mpeg',
    );
  }
}
