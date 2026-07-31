// StreamAudioSource is marked @experimental in just_audio but is the
// documented API for in-memory streaming; this is a deliberate use.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// A [StreamAudioSource] fed by the TTS pipeline.
///
/// [sourceLength] and [contentLength] stay `null` on purpose: fixed lengths
/// break dynamic streams ("Content size exceeds specified contentLength").
/// MP3 frames are self-synchronizing, so bytes appended over time play
/// gaplessly as long as the stream stays open.
class TtsStreamSource extends StreamAudioSource {
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>();
  bool _closed = false;

  TtsStreamSource() : super(tag: 'tts-stream');

  bool get isClosed => _closed;

  void addBytes(Uint8List bytes) {
    if (bytes.isEmpty || _closed) return;
    _controller.add(bytes);
  }

  Future<void> closeStream() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
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
      contentLength: null,
      offset: null,
      stream: _controller.stream,
      contentType: 'audio/mpeg',
    );
  }
}
