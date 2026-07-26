import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/tts/tts_highlighter.dart';
import 'package:noveldock/core/tts/tts_manager.dart';

void main() {
  group('TtsHighlighter', () {
    test('highlights exact sentence in HTML', () {
      const html = '<p>Hello world. This is a test paragraph.</p>';
      const sentence = 'This is a test paragraph.';

      final result = TtsHighlighter.highlight(
        html,
        sentence,
        TtsHighlightMode.sentence,
      );

      expect(result, contains('<span class="tts-highlight-sentence">This is a test paragraph.</span>'));
    });

    test('highlights specific word in second sentence correctly', () {
      const html = '<p>First sentence here. The quick brown fox jumps.</p>';
      const sentence = 'The quick brown fox jumps.';
      // Word index 2 is "brown"

      final result = TtsHighlighter.highlight(
        html,
        sentence,
        TtsHighlightMode.word,
        wordIndex: 2,
      );

      // Must contain sentence highlight
      expect(result, contains('tts-highlight-sentence'));
      // Must contain word highlight around "brown"
      expect(result, contains('<span class="tts-highlight-word">brown</span>'));
      // Should NOT highlight "First" or words in sentence 1
      expect(result, isNot(contains('<span class="tts-highlight-word">First</span>')));
      expect(result, isNot(contains('<span class="tts-highlight-word">sentence</span>')));
    });

    test('handles HTML entities smoothly', () {
      const html = '<p>Tom &amp; Jerry are friends.</p>';
      const sentence = 'Tom & Jerry are friends.';

      final result = TtsHighlighter.highlight(
        html,
        sentence,
        TtsHighlightMode.word,
        wordIndex: 1, // "Jerry" (word 0: Tom, word 1: Jerry)
      );

      expect(result, contains('<span class="tts-highlight-word">Jerry</span>'));
    });
  });
}
