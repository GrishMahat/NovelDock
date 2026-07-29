import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/utils/html_chunker.dart';

void main() {
  group('HtmlChunker', () {
    test('chunks simple paragraph', () {
      final chunks = HtmlChunker.chunkHtml('<p>Hello world.</p>');
      expect(chunks.length, 1);
      expect(chunks[0].plainText, 'Hello world.');
      expect(chunks[0].sentences, ['Hello world.']);
    });

    test('chunks multiple paragraphs', () {
      final chunks = HtmlChunker.chunkHtml('<p>First.</p><p>Second.</p>');
      expect(chunks.length, 2);
      expect(chunks[0].plainText, 'First.');
      expect(chunks[0].index, 0);
      expect(chunks[1].plainText, 'Second.');
      expect(chunks[1].index, 1);
    });

    test('chunks headings', () {
      final chunks = HtmlChunker.chunkHtml('<h1>Title</h1><p>Body.</p>');
      expect(chunks.length, 2);
      expect(chunks[0].plainText, 'Title');
    });

    test('strips HTML tags from plain text', () {
      final chunks = HtmlChunker.chunkHtml('<p><b>Bold</b> and <i>italic</i>.</p>');
      expect(chunks[0].plainText, 'Bold and italic.'); // space before period is cleaned
    });

    test('decodes HTML entities', () {
      final chunks = HtmlChunker.chunkHtml('<p>Tom &amp; Jerry</p>');
      expect(chunks[0].plainText, 'Tom & Jerry');
    });

    test('returns empty list for empty input', () {
      expect(HtmlChunker.chunkHtml(''), isEmpty);
      expect(HtmlChunker.chunkHtml('   '), isEmpty);
    });

    test('falls back to plain text when no block tags', () {
      final chunks = HtmlChunker.chunkHtml('Line one.\nLine two.');
      expect(chunks.length, 2);
    });

    test('extracts sentences correctly', () {
      final chunks = HtmlChunker.chunkHtml('<p>First sentence. Second sentence! Third?</p>');
      expect(chunks[0].sentences.length, 3);
      expect(chunks[0].sentences[0], 'First sentence.');
      expect(chunks[0].sentences[1], 'Second sentence!');
      expect(chunks[0].sentences[2], 'Third?');
    });
  });

  group('TtsChunk', () {
    test('stores all fields', () {
      const chunk = TtsChunk(index: 0, paragraphIndex: 1, text: 'Hello.', paragraphWordOffset: 0);
      expect(chunk.index, 0);
      expect(chunk.paragraphIndex, 1);
      expect(chunk.text, 'Hello.');
      expect(chunk.paragraphWordOffset, 0);
    });
  });

  group('TtsTextChunker', () {
    test('chunks single paragraph into one chunk', () {
      final chunks = TtsTextChunker.chunkForParagraphs(['Hello world.']);
      expect(chunks.length, 1);
      expect(chunks[0].text, 'Hello world.');
      expect(chunks[0].paragraphIndex, 0);
    });

    test('chunks multiple paragraphs', () {
      final chunks = TtsTextChunker.chunkForParagraphs(['First.', 'Second.', 'Third.']);
      expect(chunks.length, 3);
      expect(chunks[0].text, 'First.');
      expect(chunks[1].text, 'Second.');
      expect(chunks[2].text, 'Third.');
    });

    test('skips empty paragraphs', () {
      final chunks = TtsTextChunker.chunkForParagraphs(['One.', '', 'Three.']);
      expect(chunks.length, 2);
      expect(chunks[0].paragraphIndex, 0);
      expect(chunks[1].paragraphIndex, 2);
    });

    test('tracks paragraph word offset', () {
      final chunks = TtsTextChunker.chunkForParagraphs(['Hello world. Foo bar.']);
      expect(chunks.length, 1);
    });

    test('returns empty for no paragraphs', () {
      expect(TtsTextChunker.chunkForParagraphs([]), isEmpty);
      expect(TtsTextChunker.chunkForParagraphs(['', '  ']), isEmpty);
    });

    test('long sentences are split at comma boundaries within a paragraph', () {
      final long = 'A' * 250;
      final chunks = TtsTextChunker.chunkForParagraphs(['$long, ${'B' * 200}.']);
      expect(chunks.length, 1);
    });
  });
}
