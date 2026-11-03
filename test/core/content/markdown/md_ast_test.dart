// Tests for the AST *functions* (text extraction used by TTS and
// descriptions). The node classes themselves are plain data holders —
// the parser tests in md_parser_test.dart cover their construction.
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/content/markdown/md_ast.dart';

void main() {
  group('inlinePlainText', () {
    test('flattens formatted runs instead of dropping them', () {
      expect(
        inlinePlainText([
          TextNode('Plain '),
          BoldNode([TextNode('bold')]),
          TextNode(' '),
          ItalicNode([TextNode('italic')]),
          TextNode(' '),
          LinkNode(url: 'https://x.com', children: [TextNode('link')]),
          TextNode(' '),
          CodeNode('code'),
        ]),
        'Plain bold italic link code',
      );
    });

    test('skips images', () {
      expect(
        inlinePlainText([
          TextNode('a'),
          ImageNode(src: 'p.png', alt: 'pic'),
          TextNode('b'),
        ]),
        'ab',
      );
    });

    test('recurses into nested formatting', () {
      expect(
        inlinePlainText([
          BoldNode([
            TextNode('a'),
            ItalicNode([TextNode('b')]),
          ]),
        ]),
        'ab',
      );
    });
  });

  group('ttsParagraphs', () {
    test('flattens formatting and maps block indices', () {
      final doc = Document([
        HeadingNode(1, [TextNode('Title')]),
        ParagraphNode([TextNode('plain')]),
        ParagraphNode([
          TextNode('Say '),
          BoldNode([TextNode('this')]),
        ]),
        ParagraphNode([TextNode('   ')]),
      ]);
      final result = ttsParagraphs(doc);
      expect(result.paragraphs, ['plain', 'Say this']);
      expect(result.blockToParagraph, {1: 0, 2: 1});
    });
  });
}
