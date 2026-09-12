sealed class BlockNode {}

class ParagraphNode extends BlockNode {
  final List<InlineNode> children;
  ParagraphNode(this.children);
}

class HeadingNode extends BlockNode {
  final int level;
  final List<InlineNode> children;
  HeadingNode(this.level, this.children);
}

class BlockquoteNode extends BlockNode {
  final List<BlockNode> children;
  BlockquoteNode(this.children);
}

class HorizontalRuleNode extends BlockNode {}

class ListNode extends BlockNode {
  final bool ordered;
  final List<ListItemNode> items;
  ListNode(this.ordered, this.items);
}

class ListItemNode extends BlockNode {
  final List<InlineNode> children;
  ListItemNode(this.children);
}

class CodeFenceNode extends BlockNode {
  final String code;
  final String language;
  CodeFenceNode({required this.code, this.language = ''});
}

sealed class InlineNode {}

class ImageNode extends InlineNode {
  final String src;
  final String alt;
  ImageNode({required this.src, required this.alt});
}

class TextNode extends InlineNode {
  final String text;
  TextNode(this.text);
}

class BoldNode extends InlineNode {
  final List<InlineNode> children;
  BoldNode(this.children);
}

class ItalicNode extends InlineNode {
  final List<InlineNode> children;
  ItalicNode(this.children);
}

class LinkNode extends InlineNode {
  final String url;
  final List<InlineNode> children;
  LinkNode({required this.url, required this.children});
}

class CodeNode extends InlineNode {
  final String text;
  CodeNode(this.text);
}

class Document {
  final List<BlockNode> blocks;
  Document(this.blocks);
}

/// Paragraph texts in document order plus the block->paragraph index map:
/// the single definition of "what gets read aloud", shared by TTS start,
/// auto-advance, and highlight mapping. Headings, quotes, and lists are
/// intentionally excluded for now (tracked limitation, not an accident).
({List<String> paragraphs, Map<int, int> blockToParagraph}) ttsParagraphs(
  Document doc,
) {
  final blockToParagraph = <int, int>{};
  final paragraphs = <String>[];
  for (var i = 0; i < doc.blocks.length; i++) {
    final block = doc.blocks[i];
    if (block is! ParagraphNode) continue;
    final text = block.children.whereType<TextNode>().map((t) => t.text).join();
    if (text.trim().isEmpty) continue;
    blockToParagraph[i] = paragraphs.length;
    paragraphs.add(text);
  }
  return (paragraphs: paragraphs, blockToParagraph: blockToParagraph);
}
