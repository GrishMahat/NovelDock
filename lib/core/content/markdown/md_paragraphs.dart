import 'md_ast.dart';

/// A paragraph's plain text and its block index in the document.
class ExtractedParagraph {
  final int blockIndex;
  final String text;
  const ExtractedParagraph({required this.blockIndex, required this.text});
}

/// Extracts plain-text paragraphs from a markdown document.
///
/// The single place that flattens a [Document] into speakable/translatable
/// text. Inline formatting (bold, italic, links, code) is flattened into its
/// text. A naive `whereType<TextNode>()` scan silently drops formatted runs
/// instead. Images are skipped (no alt-text in speech/translation).
/// Empty paragraphs are omitted.
List<ExtractedParagraph> extractParagraphs(Document doc) {
  final result = <ExtractedParagraph>[];
  for (var i = 0; i < doc.blocks.length; i++) {
    final block = doc.blocks[i];
    if (block is! ParagraphNode) continue;
    final text = _inlinePlainText(block.children);
    if (text.trim().isEmpty) continue;
    result.add(ExtractedParagraph(blockIndex: i, text: text));
  }
  return result;
}

String _inlinePlainText(List<InlineNode> inlines) {
  final buffer = StringBuffer();
  void walk(List<InlineNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case TextNode():
          buffer.write(node.text);
        case BoldNode():
          walk(node.children);
        case ItalicNode():
          walk(node.children);
        case LinkNode():
          walk(node.children);
        case CodeNode():
          buffer.write(node.text);
        case ImageNode():
          break;
      }
    }
  }
  walk(inlines);
  return buffer.toString();
}