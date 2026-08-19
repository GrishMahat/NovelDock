import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/content/markdown/md_paragraphs.dart';
import 'package:noveldock/core/content/markdown/md_parser.dart';

void main() {
  group('extractParagraphs', () {
    test('extracts plain paragraph text', () {
      final doc = MDParser.parse('Hello world');
      final result = extractParagraphs(doc);
      expect(result.length, 1);
      expect(result[0].blockIndex, 0);
      expect(result[0].text, 'Hello world');
    });

    test('flattens bold/italic/link/code instead of dropping them', () {
      final doc = MDParser.parse(
        'Plain **bold** *italic* [link](https://example.com) `code` text',
      );
      final result = extractParagraphs(doc);
      expect(result.length, 1);
      expect(result[0].text, 'Plain bold italic link code text');
    });

    test('drops images from extracted text', () {
      final doc = MDParser.parse('Text ![alt](https://example.com/img.png) end');
      final result = extractParagraphs(doc);
      expect(result[0].text, 'Text  end');
    });

    test('skips non-paragraph blocks and keeps block indices', () {
      final doc = MDParser.parse('# Heading\n\nFirst para.\n\n```dart\ncode\n```\n\nLast para.');
      final result = extractParagraphs(doc);
      expect(result.map((e) => e.text), ['First para.', 'Last para.']);
      expect(result.map((e) => e.blockIndex), [1, 3]);
    });

    test('omits empty paragraphs', () {
      final doc = MDParser.parse('  \n\nReal text');
      final result = extractParagraphs(doc);
      expect(result.length, 1);
      expect(result[0].text, 'Real text');
    });
  });
}
