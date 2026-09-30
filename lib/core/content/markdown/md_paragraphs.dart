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
/// text. Per-paragraph flattening is [inlinePlainText] in `md_ast.dart` —
/// shared with TTS (`ttsParagraphs`) and annotation quotes — so formatted
/// runs (bold, italic, links, code) survive everywhere instead of being
/// silently dropped by ad-hoc `whereType<TextNode>()` scans. Images are
/// skipped (no alt-text in speech/translation). Empty paragraphs are omitted.
List<ExtractedParagraph> extractParagraphs(Document doc) {
  final result = <ExtractedParagraph>[];
  for (var i = 0; i < doc.blocks.length; i++) {
    final block = doc.blocks[i];
    if (block is! ParagraphNode) continue;
    final text = inlinePlainText(block.children);
    if (text.trim().isEmpty) continue;
    result.add(ExtractedParagraph(blockIndex: i, text: text));
  }
  return result;
}
