import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/content/markdown/md_ast.dart';

void main() {
  group('Document', () {
    test('accepts empty block list', () {
      final doc = Document([]);
      expect(doc.blocks, isEmpty);
    });

    test('accepts multiple blocks', () {
      final doc = Document([
        ParagraphNode([TextNode('a')]),
        ParagraphNode([TextNode('b')]),
      ]);
      expect(doc.blocks.length, 2);
    });
  });

  group('ParagraphNode', () {
    test('stores children', () {
      final node = ParagraphNode([TextNode('hello')]);
      expect(node.children.length, 1);
      expect((node.children[0] as TextNode).text, 'hello');
    });
  });

  group('HeadingNode', () {
    test('stores level and children', () {
      final node = HeadingNode(3, [TextNode('title')]);
      expect(node.level, 3);
      expect((node.children[0] as TextNode).text, 'title');
    });
  });

  group('BlockquoteNode', () {
    test('stores block children', () {
      final inner = ParagraphNode([TextNode('quote')]);
      final node = BlockquoteNode([inner]);
      expect(node.children.length, 1);
      expect(node.children[0], isA<ParagraphNode>());
    });
  });

  group('HorizontalRuleNode', () {
    test('has no properties', () {
      final node = HorizontalRuleNode();
      expect(node, isA<HorizontalRuleNode>());
    });
  });

  group('ListNode', () {
    test('stores ordered flag and items', () {
      final node = ListNode(true, [
        ListItemNode([TextNode('one')]),
        ListItemNode([TextNode('two')]),
      ]);
      expect(node.ordered, isTrue);
      expect(node.items.length, 2);
      expect((node.items[0].children[0] as TextNode).text, 'one');
    });

    test('unordered list', () {
      final node = ListNode(false, [
        ListItemNode([TextNode('a')]),
        ListItemNode([TextNode('b')]),
      ]);
      expect(node.ordered, isFalse);
    });
  });

  group('ListItemNode', () {
    test('stores inline children', () {
      final node = ListItemNode([TextNode('item')]);
      expect(node.children.length, 1);
      expect((node.children[0] as TextNode).text, 'item');
    });
  });

  group('CodeFenceNode', () {
    test('stores code and language', () {
      final node = CodeFenceNode(code: 'void main() {}', language: 'dart');
      expect(node.code, 'void main() {}');
      expect(node.language, 'dart');
    });

    test('defaults language to empty', () {
      final node = CodeFenceNode(code: 'text');
      expect(node.language, '');
    });
  });

  group('InlineNode types', () {
    test('TextNode stores text', () {
      final node = TextNode('hello');
      expect(node.text, 'hello');
    });

    test('BoldNode stores children', () {
      final node = BoldNode([TextNode('bold')]);
      expect((node.children[0] as TextNode).text, 'bold');
    });

    test('ItalicNode stores children', () {
      final node = ItalicNode([TextNode('italic')]);
      expect((node.children[0] as TextNode).text, 'italic');
    });

    test('LinkNode stores url and children', () {
      final node = LinkNode(url: 'https://x.com', children: [TextNode('click')]);
      expect(node.url, 'https://x.com');
      expect((node.children[0] as TextNode).text, 'click');
    });

    test('CodeNode stores text', () {
      final node = CodeNode('var x = 1;');
      expect(node.text, 'var x = 1;');
    });

    test('ImageNode stores src and alt', () {
      final node = ImageNode(src: 'pic.jpg', alt: 'A picture');
      expect(node.src, 'pic.jpg');
      expect(node.alt, 'A picture');
    });
  });
}
