import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/tts/controller.dart';

void main() {
  group('TtsPlaybackController.resumePlaylistItem', () {
    test('lands on the chunk appended after the premature EOF', () {
      // The reported case: playback ran out of audio at chunk 0 while the
      // pipeline was still synthesizing, so only chunk 0 was loaded.
      expect(
        TtsPlaybackController.resumePlaylistItem(
          pipelineFromIndex: 0,
          chunkCount: 121,
          playlistLength: 1,
        ),
        0,
      );

      // Once the pipeline appended chunk 1, the last playlist item is that
      // chunk, which is where playback has to continue.
      expect(
        TtsPlaybackController.resumePlaylistItem(
          pipelineFromIndex: 0,
          chunkCount: 121,
          playlistLength: 2,
        ),
        1,
      );
    });

    test('maps playlist items onto chunks for a mid-session resume', () {
      // Session started at chunk 5: item 2 of the playlist is chunk 7.
      expect(
        TtsPlaybackController.resumePlaylistItem(
          pipelineFromIndex: 5,
          chunkCount: 20,
          playlistLength: 3,
        ),
        2,
      );
    });

    test('never returns an item outside the playlist', () {
      expect(
        TtsPlaybackController.resumePlaylistItem(
          pipelineFromIndex: 0,
          chunkCount: 3,
          playlistLength: 9,
        ),
        2,
      );
    });

    test('reports nothing to resume for an empty playlist or session', () {
      expect(
        TtsPlaybackController.resumePlaylistItem(
          pipelineFromIndex: 0,
          chunkCount: 10,
          playlistLength: 0,
        ),
        -1,
      );

      expect(
        TtsPlaybackController.resumePlaylistItem(
          pipelineFromIndex: 0,
          chunkCount: 0,
          playlistLength: 3,
        ),
        -1,
      );
    });
  });
}
