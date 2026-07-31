import 'package:flutter/material.dart';

import '../../tts/tts_manager.dart';
import '../../../features/settings/pages/reader/reader_settings_state.dart';
import 'md_ast.dart';

TextStyle _buildTextStyle(ReaderSettings settings) {
  return TextStyle(
    fontSize: settings.fontSize,
    fontFamily: settings.fontFamily.isEmpty ? kDefaultReaderFont : settings.fontFamily,
    height: settings.lineHeight,
    color: settings.textColor,
  );
}

TextAlign _textAlign(String alignment) {
  switch (alignment) {
    case 'center': return TextAlign.center;
    case 'right': return TextAlign.right;
    case 'justify': return TextAlign.justify;
    default: return TextAlign.left;
  }
}

Widget buildDocument({
  required Document doc,
  required int chapterId,
  required int currentChapterId,
  required ReaderSettings settings,
  required TtsManagerState ttsState,
  required Map<String, GlobalKey> chunkKeys,
  required int settingsVersion,
}) {
  final textStyle = _buildTextStyle(settings);
  final align = _textAlign(settings.textAlignment);
  final isCurrentChapter = chapterId == currentChapterId;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < doc.blocks.length; i++)
        _buildBlock(
          doc.blocks[i],
          chapterId: chapterId,
          blockIndex: i,
          textStyle: textStyle,
          align: align,
          settings: settings,
          isCurrentChapter: isCurrentChapter,
          ttsState: ttsState,
          chunkKeys: chunkKeys,
        ),
    ],
  );
}

Widget _buildBlock(
  BlockNode block, {
  required int chapterId,
  required int blockIndex,
  required TextStyle textStyle,
  required TextAlign align,
  required ReaderSettings settings,
  required bool isCurrentChapter,
  required TtsManagerState ttsState,
  required Map<String, GlobalKey> chunkKeys,
}) {
  final isHighlighted = isCurrentChapter &&
      ttsState.isSpeaking &&
      blockIndex == ttsState.currentChunkIndex;

  return KeyedSubtree(
    key: chunkKeys.putIfAbsent('$chapterId-$blockIndex', () => GlobalKey()),
    child: switch (block) {
      ParagraphNode() => _buildParagraph(
          block,
          textStyle: textStyle,
          align: align,
          settings: settings,
          isHighlighted: isHighlighted,
          ttsState: ttsState,
        ),
      HeadingNode() => _buildHeading(
          block,
          textStyle: textStyle,
          settings: settings,
        ),
      BlockquoteNode() => _buildBlockquote(
          block,
          textStyle: textStyle,
          settings: settings,
        ),
      ListNode() => _buildList(block, textStyle: textStyle, settings: settings),
      HorizontalRuleNode() => _buildHR(settings),
      CodeFenceNode() => _buildCodeFence(block, settings),
      ListItemNode() => _buildParagraph(
          ParagraphNode(block.children),
          textStyle: textStyle,
          align: align,
          settings: settings,
          isHighlighted: isHighlighted,
          ttsState: ttsState,
        ),
    },
  );
}

Widget _buildParagraph(
  ParagraphNode node, {
  required TextStyle textStyle,
  required TextAlign align,
  required ReaderSettings settings,
  required bool isHighlighted,
  required TtsManagerState ttsState,
}) {
  return Padding(
    padding: EdgeInsets.only(bottom: settings.paragraphSpacing),
    child: Builder(
      builder: (context) {
        if (isHighlighted && ttsState.highlightMode == TtsHighlightMode.sentence) {
          return _highlightedRichText(
            node.children,
            textStyle: textStyle,
            align: align,
            settings: settings,
            ttsState: ttsState,
          );
        }
        if (isHighlighted && ttsState.highlightMode == TtsHighlightMode.paragraph) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _richText(
              node.children,
              textStyle: textStyle,
              align: align,
              settings: settings,
            ),
          );
        }
        return _richText(
          node.children,
          textStyle: textStyle,
          align: align,
          settings: settings,
        );
      },
    ),
  );
}

Widget _buildHeading(
  HeadingNode node, {
  required TextStyle textStyle,
  required ReaderSettings settings,
}) {
  final size = switch (node.level) { 1 => 1.6, 2 => 1.4, 3 => 1.2, _ => 1.15 };
  return Padding(
    padding: EdgeInsets.only(top: 16, bottom: 8),
    child: _richText(
      node.children,
      textStyle: textStyle.copyWith(
        fontSize: textStyle.fontSize! * size,
        fontWeight: FontWeight.bold,
      ),
      align: TextAlign.left,
      settings: settings,
    ),
  );
}

Widget _buildBlockquote(
  BlockquoteNode node, {
  required TextStyle textStyle,
  required ReaderSettings settings,
}) {
  return Padding(
    padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 3, color: settings.textColor.withValues(alpha: 0.3)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: node.children.map((b) {
              if (b is ParagraphNode) {
                return _richText(
                  b.children,
                  textStyle: textStyle.copyWith(
                    fontStyle: FontStyle.italic,
                    color: settings.textColor.withValues(alpha: 0.85),
                  ),
                  align: TextAlign.left,
                  settings: settings,
                );
              }
              return const SizedBox.shrink();
            }).toList(),
          ),
        ),
      ],
    ),
  );
}

Widget _buildList(
  ListNode node, {
  required TextStyle textStyle,
  required ReaderSettings settings,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < node.items.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    node.ordered ? '${i + 1}.' : '\u2022',
                    style: textStyle.copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _richText(
                    node.items[i].children,
                    textStyle: textStyle,
                    align: TextAlign.left,
                    settings: settings,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

Widget _buildHR(ReaderSettings settings) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Container(height: 1, color: settings.textColor.withValues(alpha: 0.2)),
  );
}

Widget _buildCodeFence(CodeFenceNode node, ReaderSettings settings) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: settings.textColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: settings.textColor.withValues(alpha: 0.1)),
      ),
      child: Text(
        node.code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.4,
          color: settings.textColor,
        ),
      ),
    ),
  );
}

Widget _buildInlineImage(ImageNode node, ReaderSettings settings) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        node.src,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Container(
          height: 100,
          color: settings.textColor.withValues(alpha: 0.05),
          child: Center(
            child: Text(
              '[${node.alt}]',
              style: TextStyle(color: settings.textColor.withValues(alpha: 0.4)),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _richText(
  List<InlineNode> inlines, {
  required TextStyle textStyle,
  required TextAlign align,
  required ReaderSettings settings,
}) {
  final spans = <InlineSpan>[];
  for (final node in inlines) {
    spans.addAll(_buildSpans(node, textStyle, settings));
  }
  return RichText(
    text: TextSpan(children: spans),
    textAlign: align,
  );
}

List<InlineSpan> _buildSpans(InlineNode node, TextStyle baseStyle, ReaderSettings settings) {
  return switch (node) {
    TextNode() => [
        if (settings.bionicReading)
          ..._bionicSpans(node.text, baseStyle)
        else
          TextSpan(text: node.text, style: baseStyle),
      ],
    BoldNode() => [
        TextSpan(
          children: node.children.expand((n) => _buildSpans(n, baseStyle, settings)).toList(),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    ItalicNode() => [
        TextSpan(
          children: node.children.expand((n) => _buildSpans(n, baseStyle, settings)).toList(),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    LinkNode() => [
        TextSpan(
          children: node.children.expand((n) => _buildSpans(n, baseStyle, settings)).toList(),
          style: baseStyle.copyWith(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          ),
        ),
      ],
    CodeNode() => [
        TextSpan(
          text: node.text,
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: baseStyle.color?.withValues(alpha: 0.08),
          ),
        ),
      ],
    ImageNode() => [
        // Images inside inline context use widget span
        WidgetSpan(
          child: _buildInlineImage(node, settings),
        ),
      ],
  };
}

List<TextSpan> _bionicSpans(String text, TextStyle style) {
  final spans = <TextSpan>[];
  final words = text.split(' ');
  for (var i = 0; i < words.length; i++) {
    if (i > 0) spans.add(TextSpan(text: ' ', style: style));
    final word = words[i];
    if (word.length <= 1) {
      spans.add(TextSpan(text: word, style: style));
    } else {
      final boldLen = (word.length / 2).ceil();
      spans.add(TextSpan(
        text: word.substring(0, boldLen),
        style: style.copyWith(fontWeight: FontWeight.bold),
      ));
      spans.add(TextSpan(
        text: word.substring(boldLen),
        style: style,
      ));
    }
  }
  return spans;
}

Widget _highlightedRichText(
  List<InlineNode> inlines, {
  required TextStyle textStyle,
  required TextAlign align,
  required ReaderSettings settings,
  required TtsManagerState ttsState,
}) {
  final spans = <InlineSpan>[];
  for (final node in inlines) {
    spans.addAll(_buildSpans(node, textStyle, settings));
  }

  final plainText = spans.map((s) => s.toPlainText()).join();
  final wordRanges = _extractWordRanges(plainText);
  final wordIndex = ttsState.currentWordIndex.clamp(0, wordRanges.length - 1);
  final sentenceRange = _findSentenceRange(plainText, wordRanges, wordIndex);

  final highlighted = <InlineSpan>[];
  int offset = 0;
  for (final span in spans) {
    final text = span.toPlainText();
    if (text.isEmpty) continue;
    final spanStart = offset;
    final spanEnd = offset + text.length;
    offset = spanEnd;

    if (span is! TextSpan) {
      highlighted.add(span);
      continue;
    }
    if (span.children != null && span.children!.isNotEmpty) {
      highlighted.add(span);
      continue;
    }

    if (sentenceRange != null && _overlaps(spanStart, spanEnd, sentenceRange.$1, sentenceRange.$2)) {
      final before = text.substring(0, (sentenceRange.$1 - spanStart).clamp(0, text.length));
      final sentenceText = text.substring(
        (sentenceRange.$1 - spanStart).clamp(0, text.length),
        (sentenceRange.$2 - spanStart).clamp(0, text.length),
      );
      final after = text.substring((sentenceRange.$2 - spanStart).clamp(0, text.length));

      if (before.isNotEmpty) highlighted.add(TextSpan(text: before, style: span.style));
      if (sentenceText.isNotEmpty) {
        if (wordRanges.isNotEmpty && wordIndex < wordRanges.length) {
          final (wStart, wEnd) = wordRanges[wordIndex];
          final localWStart = (wStart - sentenceRange.$1).clamp(0, sentenceText.length);
          final localWEnd = (wEnd - sentenceRange.$1).clamp(0, sentenceText.length);

          if (localWStart > 0) {
            highlighted.add(TextSpan(
              text: sentenceText.substring(0, localWStart),
              style: span.style?.copyWith(
                background: Paint()..color = Colors.blue.withValues(alpha: 0.22),
              ),
            ));
          }
          if (localWEnd > localWStart) {
            highlighted.add(TextSpan(
              text: sentenceText.substring(localWStart, localWEnd),
              style: span.style?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                background: Paint()..color = Colors.blue.withValues(alpha: 0.75),
              ),
            ));
          }
          if (localWEnd < sentenceText.length) {
            highlighted.add(TextSpan(
              text: sentenceText.substring(localWEnd),
              style: span.style?.copyWith(
                background: Paint()..color = Colors.blue.withValues(alpha: 0.22),
              ),
            ));
          }
        } else {
          highlighted.add(TextSpan(
            text: sentenceText,
            style: span.style?.copyWith(
              background: Paint()..color = Colors.blue.withValues(alpha: 0.22),
            ),
          ));
        }
      }
      if (after.isNotEmpty) highlighted.add(TextSpan(text: after, style: span.style));
    } else {
      highlighted.add(span);
    }
  }

  return RichText(text: TextSpan(children: highlighted), textAlign: align);
}

List<(int, int)> _extractWordRanges(String text) {
  final ranges = <(int, int)>[];
  int pos = 0;
  while (pos < text.length) {
    while (pos < text.length && text[pos] == ' ') { pos++; }
    if (pos >= text.length) break;
    final start = pos;
    while (pos < text.length && text[pos] != ' ') { pos++; }
    ranges.add((start, pos));
  }
  return ranges;
}

(int, int)? _findSentenceRange(String text, List<(int, int)> wordRanges, int wordIndex) {
  if (wordRanges.isEmpty || wordIndex >= wordRanges.length) return null;
  final (wStart, _) = wordRanges[wordIndex];

  int sStart = 0;
  for (int i = wStart - 1; i >= 1; i--) {
    final ch = text[i];
    final prev = text[i - 1];
    if ((prev == '.' || prev == '!' || prev == '?') && ch == ' ') {
      sStart = i + 1;
      break;
    }
  }

  int sEnd = text.length;
  for (int i = wStart; i < text.length; i++) {
    final ch = text[i];
    if (ch == '.' || ch == '!' || ch == '?') {
      sEnd = i + 1;
      break;
    }
  }

  if (sStart >= sEnd) return null;
  return (sStart, sEnd);
}

bool _overlaps(int aStart, int aEnd, int bStart, int bEnd) {
  return aStart < bEnd && bStart < aEnd;
}
