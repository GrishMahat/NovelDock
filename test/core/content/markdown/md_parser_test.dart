import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/content/markdown/md_ast.dart';
import 'package:noveldock/core/content/markdown/md_parser.dart';

void main() {
  group('MDParser', () {
    test('parses plain paragraph', () {
      final doc = MDParser.parse('Hello world');
      expect(doc.blocks.length, 1);
      expect(doc.blocks[0], isA<ParagraphNode>());
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children.length, 1);
      expect(p.children[0], isA<TextNode>());
      expect((p.children[0] as TextNode).text, 'Hello world');
    });

    test('parses heading levels 1-6', () {
      for (int i = 1; i <= 6; i++) {
        final md = '${'#' * i} Heading $i';
        final doc = MDParser.parse(md);
        expect(doc.blocks.length, 1, reason: 'for level $i');
        expect(doc.blocks[0], isA<HeadingNode>());
        final h = doc.blocks[0] as HeadingNode;
        expect(h.level, i);
        expect((h.children[0] as TextNode).text, 'Heading $i');
      }
    });

    test('parses bold (**text**)', () {
      final doc = MDParser.parse('This is **bold** text');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children.length, 3);
      expect(p.children[0], isA<TextNode>());
      expect((p.children[0] as TextNode).text, 'This is ');
      expect(p.children[1], isA<BoldNode>());
      expect((p.children[1] as BoldNode).children[0], isA<TextNode>());
      expect(
        ((p.children[1] as BoldNode).children[0] as TextNode).text,
        'bold',
      );
      expect(p.children[2], isA<TextNode>());
      expect((p.children[2] as TextNode).text, ' text');
    });

    test('parses italic (*text*)', () {
      final doc = MDParser.parse('This is *italic* text');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children.length, 3);
      expect(p.children[1], isA<ItalicNode>());
      expect(
        ((p.children[1] as ItalicNode).children[0] as TextNode).text,
        'italic',
      );
    });

    test('parses bold with underscores (__text__)', () {
      final doc = MDParser.parse('This is __bold__ text');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children[1], isA<BoldNode>());
      expect(
        ((p.children[1] as BoldNode).children[0] as TextNode).text,
        'bold',
      );
    });

    test('parses italic with underscores (_text_)', () {
      final doc = MDParser.parse('This is _italic_ text');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children[1], isA<ItalicNode>());
    });

    test('parses inline code', () {
      final doc = MDParser.parse('Use `code` here');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children[1], isA<CodeNode>());
      expect((p.children[1] as CodeNode).text, 'code');
    });

    test('parses link [text](url)', () {
      final doc = MDParser.parse('Click [here](https://example.com) now');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children.length, 3);
      expect(p.children[1], isA<LinkNode>());
      final link = p.children[1] as LinkNode;
      expect(link.url, 'https://example.com');
      expect((link.children[0] as TextNode).text, 'here');
    });

    test('parses code fence with language', () {
      final md = '```dart\nvoid main() {}\n```';
      final doc = MDParser.parse(md);
      expect(doc.blocks.length, 1);
      expect(doc.blocks[0], isA<CodeFenceNode>());
      final code = doc.blocks[0] as CodeFenceNode;
      expect(code.language, 'dart');
      expect(code.code.trim(), 'void main() {}');
    });

    test('parses code fence without language', () {
      final md = '```\nplain code\n```';
      final doc = MDParser.parse(md);
      final code = doc.blocks[0] as CodeFenceNode;
      expect(code.language, '');
      expect(code.code.trim(), 'plain code');
    });

    test('parses blockquote', () {
      final md = '> This is a quote';
      final doc = MDParser.parse(md);
      expect(doc.blocks[0], isA<BlockquoteNode>());
      final bq = doc.blocks[0] as BlockquoteNode;
      expect(bq.children.length, 1);
      expect(bq.children[0], isA<ParagraphNode>());
    });

    test('parses nested blockquote', () {
      final md = '> Outer\n> > Inner';
      final doc = MDParser.parse(md);
      final bq = doc.blocks[0] as BlockquoteNode;
      expect(bq.children.length, 2);
      expect(bq.children[0], isA<ParagraphNode>());
      expect(bq.children[1], isA<BlockquoteNode>());
    });

    test('parses unordered list', () {
      final md = '- Item one\n- Item two\n- Item three';
      final doc = MDParser.parse(md);
      expect(doc.blocks[0], isA<ListNode>());
      final list = doc.blocks[0] as ListNode;
      expect(list.ordered, isFalse);
      expect(list.items.length, 3);
      expect((list.items[0].children[0] as TextNode).text, 'Item one');
      expect((list.items[1].children[0] as TextNode).text, 'Item two');
      expect((list.items[2].children[0] as TextNode).text, 'Item three');
    });

    test('parses horizontal rule', () {
      final doc = MDParser.parse('---');
      expect(doc.blocks[0], isA<HorizontalRuleNode>());
    });

    test('handles multiple blocks', () {
      final md = '# Title\n\nParagraph text.\n\n> Quote here.';
      final doc = MDParser.parse(md);
      expect(doc.blocks.length, 3);
      expect(doc.blocks[0], isA<HeadingNode>());
      expect(doc.blocks[1], isA<ParagraphNode>());
      expect(doc.blocks[2], isA<BlockquoteNode>());
    });

    test('escaped characters', () {
      final doc = MDParser.parse(r'This \*is\* literal');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children.length, 1);
      expect(p.children[0], isA<TextNode>());
      expect((p.children[0] as TextNode).text, 'This *is* literal');
    });

    test('empty input returns empty document', () {
      final doc = MDParser.parse('');
      expect(doc.blocks.isEmpty, true);
    });

    test('parses bold+italic combined ***text***', () {
      final doc = MDParser.parse('This ***is*** important');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children[1], isA<BoldNode>());
      final bold = p.children[1] as BoldNode;
      // Parser consumes ** first, leaving *is as inner text
      expect(bold.children[0], isA<TextNode>());
      expect((bold.children[0] as TextNode).text, '*is');
    });

    test('parses link with bold text', () {
      final doc = MDParser.parse('[**bold link**](https://x.com)');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children[0], isA<LinkNode>());
      final link = p.children[0] as LinkNode;
      expect(link.url, 'https://x.com');
      expect((link.children[0] as BoldNode).children[0], isA<TextNode>());
      expect(
        ((link.children[0] as BoldNode).children[0] as TextNode).text,
        'bold link',
      );
    });

    test('parses multiple paragraphs separated by blank line', () {
      final doc = MDParser.parse('First para.\n\nSecond para.');
      expect(doc.blocks.length, 2);
      expect((doc.blocks[0] as ParagraphNode).children[0], isA<TextNode>());
      expect(
        ((doc.blocks[0] as ParagraphNode).children[0] as TextNode).text,
        'First para.',
      );
      expect((doc.blocks[1] as ParagraphNode).children[0], isA<TextNode>());
      expect(
        ((doc.blocks[1] as ParagraphNode).children[0] as TextNode).text,
        'Second para.',
      );
    });

    test('parses bold inside italic', () {
      final doc = MDParser.parse('*italic and **bold** inside*');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children[0], isA<ItalicNode>());
      final italic = p.children[0] as ItalicNode;
      expect((italic.children[0] as TextNode).text, 'italic and ');
      expect(italic.children[1], isA<BoldNode>());
      expect((italic.children[2] as TextNode).text, ' inside');
    });

    test('parses italic inside bold', () {
      final doc = MDParser.parse('**bold and *italic* inside**');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children[0], isA<BoldNode>());
      final bold = p.children[0] as BoldNode;
      expect(bold.children[1], isA<ItalicNode>());
    });

    test('handles multiple inline code spans', () {
      final doc = MDParser.parse('Use `code` and `more code` here');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children[1], isA<CodeNode>());
      expect((p.children[1] as CodeNode).text, 'code');
      expect(p.children[3], isA<CodeNode>());
      expect((p.children[3] as CodeNode).text, 'more code');
    });

    test('parses image', () {
      final doc = MDParser.parse('An image: ![alt](img.jpg)');
      final p = doc.blocks[0] as ParagraphNode;
      expect(p.children.length, 2);
      expect(p.children[0], isA<TextNode>());
      expect((p.children[0] as TextNode).text, 'An image: ');
      expect(p.children[1], isA<ImageNode>());
      final img = p.children[1] as ImageNode;
      expect(img.src, 'img.jpg');
      expect(img.alt, 'alt');
    });

    test('handles only whitespace input', () {
      final doc = MDParser.parse('   \n\n  \n');
      expect(doc.blocks.isEmpty, true);
    });

    test('parses ordered list', () {
      final doc = MDParser.parse('1. First\n2. Second\n3. Third');
      expect(doc.blocks[0], isA<ListNode>());
      final list = doc.blocks[0] as ListNode;
      expect(list.ordered, isTrue);
      expect(list.items.length, 3);
      expect((list.items[0].children[0] as TextNode).text, 'First');
      expect((list.items[1].children[0] as TextNode).text, 'Second');
      expect((list.items[2].children[0] as TextNode).text, 'Third');
    });

    test('parses heading without space after #', () {
      final doc = MDParser.parse('#NoSpace');
      expect(doc.blocks[0], isA<HeadingNode>());
      final h = doc.blocks[0] as HeadingNode;
      expect(h.level, 1);
      expect((h.children[0] as TextNode).text, 'NoSpace');
    });
  });
}
