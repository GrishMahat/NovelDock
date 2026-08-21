import 'md_ast.dart';

class MDParser {
  static Document parse(String md) {
    final lines = md.split('\n');
    final blocks = <BlockNode>[];
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];

      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      if (line.trim() == '---' ||
          line.trim() == '***' ||
          line.trim() == '___' ||
          line.trim() == '- - -' ||
          line.trim() == '* * *' ||
          line.trim() == '_ _ _') {
        blocks.add(HorizontalRuleNode());
        i++;
        continue;
      }

      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        final (fence, next) = _parseCodeFence(lines, i);
        blocks.add(fence);
        i = next;
        continue;
      }

      if (trimmed.startsWith('#')) {
        final (heading, _) = _parseHeading(line);
        blocks.add(heading);
        i++;
        continue;
      }

      if (trimmed.startsWith('>')) {
        final (bq, next) = _parseBlockquote(lines, i);
        blocks.add(bq);
        i = next;
        continue;
      }

      if (trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.startsWith('+ ') ||
          RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        final (list, next) = _parseList(lines, i);
        blocks.add(list);
        i = next;
        continue;
      }

      final (para, next) = _parseParagraph(lines, i);
      blocks.add(para);
      i = next;
    }

    return Document(blocks);
  }

  static (BlockNode, int) _parseHeading(String line) {
    int level = 0;
    for (int j = 0; j < line.length && line[j] == '#'; j++) {
      level++;
    }
    level = level.clamp(1, 6);
    String content;
    if (level < line.length && line[level] == ' ') {
      content = line.substring(level + 1);
    } else if (level < line.length) {
      content = line.substring(level);
    } else {
      content = '';
    }
    final inlines = _parseInlines(content.trim());
    return (HeadingNode(level, inlines), 1);
  }

  static (BlockquoteNode, int) _parseBlockquote(List<String> lines, int start) {
    final children = <BlockNode>[];
    final quoteLines = <String>[];
    int i = start;

    while (i < lines.length) {
      final trimmed = lines[i].trim();
      if (!trimmed.startsWith('>')) break;

      if (trimmed.startsWith('> >')) {
        if (quoteLines.isNotEmpty) {
          final inlines = _parseInlines(quoteLines.join(' ').trim());
          children.add(ParagraphNode(inlines));
          quoteLines.clear();
        }
        final nestedLines = <String>[];
        while (i < lines.length) {
          final l = lines[i].trim();
          if (!l.startsWith('>')) break;
          nestedLines.add(l.length > 2 ? l.substring(2) : '');
          i++;
        }
        final (nested, _) = _parseBlockquote(nestedLines, 0);
        children.add(nested);
        continue;
      }

      var content = trimmed.substring(1);
      if (content.startsWith(' ')) content = content.substring(1);
      quoteLines.add(content);
      i++;
    }

    if (quoteLines.isNotEmpty) {
      final merged = quoteLines.join(' ').trim();
      final inlines = _parseInlines(merged);
      children.add(ParagraphNode(inlines));
    }

    return (BlockquoteNode(children), i);
  }

  static (BlockNode, int) _parseList(List<String> lines, int start) {
    final isOrdered = RegExp(r'^\d+\.\s').hasMatch(lines[start].trim());
    final items = <_ListItem>[];
    int i = start;

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      final orderedMatch = RegExp(r'^(\d+)\.\s(.*)').firstMatch(trimmed);
      final unorderedMatch = RegExp(r'^[-*+]\s(.*)').firstMatch(trimmed);
      final indent = line.length - line.trimLeft().length;

      if (orderedMatch == null && unorderedMatch == null) {
        if (trimmed.isEmpty || indent <= 0) break;
        if (items.isNotEmpty) {
          items.last.textLines.add(trimmed);
        }
        i++;
        continue;
      }

      final content = orderedMatch?.group(2) ?? unorderedMatch?.group(1) ?? '';
      items.add(_ListItem(content, indent));
      i++;

      while (i < lines.length) {
        final next = lines[i];
        final nextTrimmed = next.trim();
        final nextIndent = next.length - next.trimLeft().length;
        if (nextTrimmed.isEmpty) {
          i++;
          break;
        }
        if ((RegExp(r'^\d+\.\s').hasMatch(nextTrimmed) ||
                RegExp(r'^[-*+]\s').hasMatch(nextTrimmed)) &&
            nextIndent == indent) {
          break;
        }
        items.last.textLines.add(nextTrimmed);
        i++;
      }
    }

    final listItems = <ListItemNode>[];
    for (final item in items) {
      final text = item.textLines.join(' ').trim();
      final inlines = text.isNotEmpty
          ? _parseInlines(text)
          : <InlineNode>[TextNode('')];
      listItems.add(ListItemNode(inlines));
    }

    return (ListNode(isOrdered, listItems), i);
  }

  static (BlockNode, int) _parseParagraph(List<String> lines, int start) {
    final textLines = <String>[];
    int i = start;

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) break;
      if (trimmed.startsWith('#')) {
        final (saved, _) = _parseHeading(line);
        if (saved is HeadingNode && saved.level > 0) break;
      }
      if (trimmed.startsWith('>')) break;
      if (trimmed.startsWith('```')) break;
      if (trimmed.startsWith('- ') ||
          trimmed.startsWith('* ') ||
          trimmed.startsWith('+ ') ||
          RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        break;
      }
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') break;
      textLines.add(line);
      i++;
    }

    final text = textLines.join('\n').trim();
    if (text.isEmpty) return (ParagraphNode([]), i);

    final inlines = _parseInlines(text);
    return (ParagraphNode(inlines), i);
  }

  static (BlockNode, int) _parseCodeFence(List<String> lines, int start) {
    final first = lines[start].trim();
    final lang = first.length > 3 ? first.substring(3).trim() : '';
    final codeLines = <String>[];
    int i = start + 1;

    while (i < lines.length) {
      if (lines[i].trim() == '```') {
        i++;
        break;
      }
      codeLines.add(lines[i]);
      i++;
    }

    return (CodeFenceNode(code: codeLines.join('\n'), language: lang), i);
  }

  static List<InlineNode> _parseInlines(String text) {
    final result = <InlineNode>[];
    int i = 0;
    final textBuf = StringBuffer();

    void flushText() {
      if (textBuf.isNotEmpty) {
        result.add(TextNode(textBuf.toString()));
        textBuf.clear();
      }
    }

    while (i < text.length) {
      final c = text[i];

      if (c == '\\' && i + 1 < text.length) {
        textBuf.write(text[i + 1]);
        i += 2;
        continue;
      }

      if (c == '`') {
        final end = text.indexOf('`', i + 1);
        if (end > i) {
          flushText();
          result.add(CodeNode(text.substring(i + 1, end)));
          i = end + 1;
          continue;
        }
        textBuf.write('`');
        i++;
        continue;
      }

      if (c == '!' && i + 1 < text.length && text[i + 1] == '[') {
        final close = text.indexOf(']', i + 2);
        if (close > i + 2 &&
            close + 1 < text.length &&
            text[close + 1] == '(') {
          final parenClose = text.indexOf(')', close + 2);
          if (parenClose > close + 2) {
            final alt = text.substring(i + 2, close);
            final src = text.substring(close + 2, parenClose);
            flushText();
            result.add(ImageNode(src: src, alt: alt));
            i = parenClose + 1;
            continue;
          }
        }
      }

      if (c == '[') {
        final close = text.indexOf(']', i + 1);
        if (close > i + 1 &&
            close + 1 < text.length &&
            text[close + 1] == '(') {
          final parenClose = text.indexOf(')', close + 2);
          if (parenClose > close + 2) {
            final linkText = text.substring(i + 1, close);
            final url = text.substring(close + 2, parenClose);
            flushText();
            result.add(LinkNode(url: url, children: _parseInlines(linkText)));
            i = parenClose + 1;
            continue;
          }
        }
      }

      if ((c == '*' || c == '_') && i + 1 < text.length && (text[i + 1] == c)) {
        final delimiter = text.substring(i, i + 2);
        if (i + 2 < text.length) {
          final end = _findDelimiter(text, delimiter, i + 2);
          if (end > i + 2) {
            final inner = text.substring(i + 2, end);
            flushText();
            result.add(BoldNode(_parseInlines(inner)));
            i = end + 2;
            continue;
          }
        }
        textBuf.write(delimiter);
        i += 2;
        continue;
      }

      if (c == '*' || c == '_') {
        final end = _findDelimiter(text, c.toString(), i + 1);
        if (end > i + 1 && !(i > 0 && text[i - 1] == c)) {
          final inner = text.substring(i + 1, end);
          flushText();
          result.add(ItalicNode(_parseInlines(inner)));
          i = end + 1;
          continue;
        }
        textBuf.write(c);
        i++;
        continue;
      }

      textBuf.write(c);
      i++;
    }

    flushText();
    return result;
  }

  static int _findDelimiter(String text, String delimiter, int start) {
    final isDouble = delimiter.length == 2;
    for (int i = start; i < text.length - (isDouble ? 1 : 0); i++) {
      if (text[i] == '\\') {
        i++;
        continue;
      }
      if (isDouble) {
        if (text[i] == delimiter[0] && text[i + 1] == delimiter[1]) {
          return i;
        }
      } else {
        if (text[i] == delimiter) {
          if (i + 1 < text.length && text[i + 1] == delimiter) {
            i++;
            continue;
          }
          return i;
        }
      }
    }
    return -1;
  }
}

class _ListItem {
  final String content;
  final int indent;
  final List<String> textLines;
  _ListItem(this.content, this.indent) : textLines = [content];
}
