import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../tts/tts_manager.dart';
import '../../../features/settings/pages/reader/reader_settings_state.dart';
import '../../database/database.dart';
import '../../../theme/app_theme.dart';
import 'md_ast.dart';

TextStyle _buildTextStyle(ReaderSettings settings) {
  return TextStyle(
    fontSize: settings.fontSize,
    fontFamily: settings.fontFamily.isEmpty
        ? kDefaultReaderFont
        : settings.fontFamily,
    height: settings.lineHeight,
    color: settings.textColor,
  );
}

TextAlign _textAlign(String alignment) {
  switch (alignment) {
    case 'center':
      return TextAlign.center;
    case 'right':
      return TextAlign.right;
    case 'justify':
      return TextAlign.justify;
    default:
      return TextAlign.left;
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
  Map<int, int>? blockToParagraph,
  // Reader highlights, this chapter: paragraph ordinal -> row. Ordinals
  // match ttsParagraphs (nth top-level ParagraphNode), so highlights and
  // read-aloud agree on paragraph identity.
  Map<int, Annotation>? annotationsByParagraph,
  void Function(int chapterId, int paragraphIndex, String text)?
  onAnnotateParagraph,
}) {
  final textStyle = _buildTextStyle(settings);
  final align = _textAlign(settings.textAlignment);
  final isCurrentChapter = chapterId == currentChapterId;

  // Paragraph ordinals (nth top-level ParagraphNode) computed eagerly:
  // Builder closures below run lazily and repeatedly, so no counting there.
  final paragraphOrdinals = <int, int>{};
  var ordinal = 0;
  for (var i = 0; i < doc.blocks.length; i++) {
    if (doc.blocks[i] is ParagraphNode) {
      paragraphOrdinals[i] = ordinal++;
    }
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < doc.blocks.length; i++)
        _buildBlock(
          doc.blocks[i],
          chapterId: chapterId,
          blockIndex: i,
          paragraphIndex: paragraphOrdinals[i],
          textStyle: textStyle,
          align: align,
          settings: settings,
          isCurrentChapter: isCurrentChapter,
          ttsState: ttsState,
          chunkKeys: chunkKeys,
          blockToParagraph: blockToParagraph,
          annotation: paragraphOrdinals[i] == null
              ? null
              : annotationsByParagraph?[paragraphOrdinals[i]!],
          onAnnotateParagraph: onAnnotateParagraph,
        ),
    ],
  );
}

Widget _buildBlock(
  BlockNode block, {
  required int chapterId,
  required int blockIndex,
  required int? paragraphIndex,
  required TextStyle textStyle,
  required TextAlign align,
  required ReaderSettings settings,
  required bool isCurrentChapter,
  required TtsManagerState ttsState,
  required Map<String, GlobalKey> chunkKeys,
  Map<int, int>? blockToParagraph,
  Annotation? annotation,
  void Function(int chapterId, int paragraphIndex, String text)?
  onAnnotateParagraph,
}) {
  // TTS chunks are indexed by paragraph (skipping headings etc.), so map the
  // block index to its paragraph index before comparing with the current chunk.
  final isParagraph = block is ParagraphNode;
  final paragraphIndex = isParagraph ? (blockToParagraph?[blockIndex]) : null;
  final isHighlighted =
      isCurrentChapter &&
      ttsState.isSpeaking &&
      paragraphIndex != null &&
      paragraphIndex == ttsState.currentChunkIndex;

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
        chapterId: chapterId,
        paragraphIndex: paragraphIndex,
        annotation: annotation,
        onAnnotateParagraph: onAnnotateParagraph,
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
  int? chapterId,
  int? paragraphIndex,
  Annotation? annotation,
  void Function(int chapterId, int paragraphIndex, String text)?
  onAnnotateParagraph,
}) {
  // Plain paragraph text for quotes/long-press payloads.
  String plainText() =>
      node.children.whereType<TextNode>().map((n) => n.text).join().trim();

  Widget frame(Widget content) {
    // Reader highlight: distinct from the blue TTS tint so the two never
    // visually collide (amber wash; greys gracefully on e-ink).
    final annotated = annotation != null;
    final framed = annotated
        ? Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE8B93C).withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(4),
            ),
            child: content,
          )
        : content;
    // Long-press to highlight/annotate. Only when the reader supplied a
    // handler and this paragraph has a stable identity.
    if (onAnnotateParagraph == null ||
        chapterId == null ||
        paragraphIndex == null) {
      return framed;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () =>
          onAnnotateParagraph(chapterId, paragraphIndex, plainText()),
      child: framed,
    );
  }

  return Padding(
    padding: EdgeInsets.only(bottom: settings.paragraphSpacing),
    child: Builder(
      builder: (context) {
        if (isHighlighted &&
            ttsState.highlightMode == TtsHighlightMode.sentence) {
          return frame(
            _highlightedRichText(
              node.children,
              textStyle: textStyle,
              align: align,
              settings: settings,
              ttsState: ttsState,
            ),
          );
        }
        if (isHighlighted &&
            ttsState.highlightMode == TtsHighlightMode.paragraph) {
          return Container(
            decoration: BoxDecoration(
              color: AppTheme.kReaderAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: frame(
              _richText(
                node.children,
                textStyle: textStyle,
                align: align,
                settings: settings,
              ),
            ),
          );
        }
        return frame(
          _richText(
            node.children,
            textStyle: textStyle,
            align: align,
            settings: settings,
          ),
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
  final size = switch (node.level) {
    1 => 1.6,
    2 => 1.4,
    3 => 1.2,
    _ => 1.15,
  };
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
    child: Container(
      height: 1,
      color: settings.textColor.withValues(alpha: 0.2),
    ),
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
              style: TextStyle(
                color: settings.textColor.withValues(alpha: 0.4),
              ),
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

/// Opens a chapter link externally. Links are styled as tappable affordances,
/// so they must act like it; failed launches stay silent (logged) rather
/// than stranding the reader on a dead tap.
Future<void> _openLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

List<InlineSpan> _buildSpans(
  InlineNode node,
  TextStyle baseStyle,
  ReaderSettings settings,
) {
  return switch (node) {
    TextNode() => [
      if (settings.bionicReading)
        ..._bionicSpans(node.text, baseStyle)
      else
        TextSpan(text: node.text, style: baseStyle),
    ],
    BoldNode() => [
      TextSpan(
        children: node.children
            .expand((n) => _buildSpans(n, baseStyle, settings))
            .toList(),
        style: baseStyle.copyWith(fontWeight: FontWeight.bold),
      ),
    ],
    ItalicNode() => [
      TextSpan(
        children: node.children
            .expand((n) => _buildSpans(n, baseStyle, settings))
            .toList(),
        style: baseStyle.copyWith(fontStyle: FontStyle.italic),
      ),
    ],
    LinkNode() => [
      TextSpan(
        children: node.children
            .expand((n) => _buildSpans(n, baseStyle, settings))
            .toList(),
        style: baseStyle.copyWith(
          color: AppTheme.kReaderAccent,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _openLink(node.url),
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
      WidgetSpan(child: _buildInlineImage(node, settings)),
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
      spans.add(
        TextSpan(
          text: word.substring(0, boldLen),
          style: style.copyWith(fontWeight: FontWeight.bold),
        ),
      );
      spans.add(TextSpan(text: word.substring(boldLen), style: style));
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
  final wordIndex = wordRanges.isEmpty
      ? 0
      : ttsState.currentWordIndex.clamp(0, wordRanges.length - 1);
  final sentenceRange = _sentenceRangeForState(plainText, ttsState, wordIndex);

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

    if (sentenceRange != null &&
        _overlaps(spanStart, spanEnd, sentenceRange.$1, sentenceRange.$2)) {
      final before = text.substring(
        0,
        (sentenceRange.$1 - spanStart).clamp(0, text.length),
      );
      final sentenceText = text.substring(
        (sentenceRange.$1 - spanStart).clamp(0, text.length),
        (sentenceRange.$2 - spanStart).clamp(0, text.length),
      );
      final after = text.substring(
        (sentenceRange.$2 - spanStart).clamp(0, text.length),
      );

      if (before.isNotEmpty) {
        highlighted.add(TextSpan(text: before, style: span.style));
      }
      if (sentenceText.isNotEmpty) {
        highlighted.add(
          TextSpan(
            text: sentenceText,
            style: span.style?.copyWith(
              background: Paint()
                ..color = AppTheme.kReaderAccent.withValues(alpha: 0.22),
            ),
          ),
        );
      }
      if (after.isNotEmpty) {
        highlighted.add(TextSpan(text: after, style: span.style));
      }
    } else {
      highlighted.add(span);
    }
  }

  return RichText(
    text: TextSpan(children: highlighted),
    textAlign: align,
  );
}

List<(int, int)> _extractWordRanges(String text) {
  final ranges = <(int, int)>[];
  int pos = 0;
  while (pos < text.length) {
    while (pos < text.length && text[pos] == ' ') {
      pos++;
    }
    if (pos >= text.length) break;
    final start = pos;
    while (pos < text.length && text[pos] != ' ') {
      pos++;
    }
    ranges.add((start, pos));
  }
  return ranges;
}

(int, int)? _sentenceRangeForState(
  String text,
  TtsManagerState state,
  int wordIndex,
) {
  final start = state.currentChunkStartOffset.clamp(0, text.length);
  final end = state.currentChunkEndOffset.clamp(start, text.length);
  if (end > start) return (start, end);

  return _findSentenceRange(text, _extractWordRanges(text), wordIndex);
}

(int, int)? _findSentenceRange(
  String text,
  List<(int, int)> wordRanges,
  int wordIndex,
) {
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
