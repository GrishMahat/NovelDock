import 'package:flutter_test/flutter_test.dart';

import 'package:noveldock/core/tts/chunker.dart';

void main() {
  const chunker = TtsChunker(
    targetMs: 300,
    softMaxMs: 500,
    hardMaxChars: 100,
    charsPerSecond: 10,
  );

  group('TtsChunker', () {
    test('short paragraph becomes a single chunk', () {
      final chunks = chunker.chunkParagraphs(['Hello world.']);
      expect(chunks, hasLength(1));
      final c = chunks.single;
      expect(c.index, 0);
      expect(c.paragraphIndex, 0);
      expect(c.text, 'Hello world.');
      expect(c.startOffset, 0);
      expect(c.endOffset, 'Hello world.'.length);
      expect(c.paragraphWordOffset, 0);
      expect(c.sentenceCount, 1);
    });

    test('long paragraph packs sentences into chunks at sentence boundaries',
        () {
      final chunks = chunker.chunkParagraphs(['Aaa. Bbb. Ccc.']);
      expect(chunks, hasLength(3));
      expect(chunks[0].text, 'Aaa.');
      expect(chunks[1].text, ' Bbb.');
      expect(chunks[2].text, ' Ccc.');
      expect(chunks[0].paragraphWordOffset, 0);
      expect(chunks[1].paragraphWordOffset, 1);
      expect(chunks[2].paragraphWordOffset, 2);
      expect(chunks[0].sentenceCount, 1);
      expect(chunks[0].startOffset, 0);
      expect(chunks[0].endOffset, 4);
      expect(chunks[1].startOffset, 4);
      expect(chunks[1].endOffset, 9);
    });

    test('period inside a number is not a sentence boundary', () {
      final chunks = chunker.chunkParagraphs(['Pi is 3.14. Done.']);
      expect(chunks, hasLength(2));
      expect(chunks[0].text, 'Pi is 3.14.');
    });

    test('CJK sentence punctuation splits sentences', () {
      final chunks = chunker.chunkParagraphs(['第一句。第二句！第三句？']);
      expect(chunks, hasLength(3));
      expect(chunks[0].text, '第一句。');
      expect(chunks[1].text, '第二句！');
      expect(chunks[2].text, '第三句？');
    });

    test('oversize sentence without punctuation is hard-split at last space',
        () {
      final text = '${'word ' * 60}fin';
      final chunks = chunker.chunkParagraphs([text]);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.text.length, lessThanOrEqualTo(100));
      }
      expect(chunks.map((c) => c.text).join(), text);
    });

    test('oversize CJK sentence is hard-split at the char cap', () {
      final text = '汉' * 250;
      final chunks = chunker.chunkParagraphs([text]);
      expect(chunks, hasLength(3));
      for (final c in chunks) {
        expect(c.text.length, lessThanOrEqualTo(100));
      }
      expect(chunks.map((c) => c.text).join(), text);
    });

    test('oversize sentence with clauses splits at clause boundaries', () {
      final text = '${'clause, ' * 40}end.';
      final chunks = chunker.chunkParagraphs([text]);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.text.length, lessThanOrEqualTo(100));
      }
      expect(chunks.map((c) => c.text).join(), text);
    });

    test('empty and whitespace-only paragraphs are skipped', () {
      final chunks = chunker.chunkParagraphs(['', '   ', 'Xxx.']);
      expect(chunks, hasLength(1));
      expect(chunks.single.index, 0);
      expect(chunks.single.paragraphIndex, 2);
    });

    test('paragraph word offsets restart per paragraph', () {
      final chunks = chunker.chunkParagraphs(['Aaa. Bbb. Ccc.', 'Xxx.']);
      expect(chunks, hasLength(4));
      expect(chunks[3].paragraphIndex, 1);
      expect(chunks[3].paragraphWordOffset, 0);
      expect(chunks[3].index, 3);
    });

    test('estimated duration scales with speed', () {
      final chunks1 = chunker.chunkParagraphs(['Hello world.']);
      final chunks2 =
          chunker.chunkParagraphs(['Hello world.'], speed: 2.0);
      expect(chunks1.single.estimatedDurationMs,
          chunks2.single.estimatedDurationMs * 2);
    });
  });
}
