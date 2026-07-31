import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class Html2Md {
  static String convert(String html) {
    if (html.trim().isEmpty) return '';

    final doc = html_parser.parse(html);
    final body = doc.body;
    if (body == null) return '';

    final buffer = StringBuffer();
    _renderNodes(body.nodes, buffer, indent: 0);
    return buffer.toString().trim();
  }

  static void _renderNodes(List<dom.Node> nodes, StringBuffer buf, {int indent = 0}) {
    for (final node in nodes) {
      if (node is dom.Element) {
        _renderElement(node, buf, indent: indent);
      } else if (node is dom.Text) {
        final text = _escapeMd(node.text.trim());
        if (text.isNotEmpty) {
          buf.write(text);
        }
      }
    }
  }

  static void _renderElement(dom.Element el, StringBuffer buf, {int indent = 0}) {
    final tag = el.localName ?? '';

    switch (tag) {
      case 'script':
      case 'style':
      case 'nav':
      case 'header':
      case 'footer':
      case 'aside':
      case 'form':
      case 'select':
      case 'button':
      case 'iframe':
      case 'noscript':
        return;

      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(tag[1]);
        _newline(buf);
        buf.write('${'#' * level} ');
        _renderInline(el.nodes, buf);
        buf.writeln();
        buf.writeln();
        return;

      case 'p':
        _newline(buf);
        _renderInline(el.nodes, buf);
        buf.writeln();
        buf.writeln();
        return;

      case 'div':
      case 'section':
      case 'article':
        _renderNodes(el.nodes, buf, indent: indent);
        return;

      case 'br':
        buf.write('  ');
        buf.writeln();
        return;

      case 'hr':
        _newline(buf);
        buf.write('---');
        _newline(buf);
        _newline(buf);
        return;

      case 'blockquote':
        _newline(buf);
        _renderBlockquote(el.nodes, buf);
        _newline(buf);
        return;

      case 'ul':
        _newline(buf);
        _renderList(el.nodes, buf, ordered: false, indent: indent);
        _newline(buf);
        return;

      case 'ol':
        _newline(buf);
        _renderList(el.nodes, buf, ordered: true, indent: indent);
        _newline(buf);
        return;

      case 'li':
        return;

      case 'img':
        final src = el.attributes['src'] ?? '';
        final alt = el.attributes['alt'] ?? '';
        if (src.isNotEmpty) {
          buf.write('![${_escapeMd(alt)}](${_escapeUrl(src)})');
        }
        return;

      case 'a':
        final href = el.attributes['href'] ?? '';
        final inner = StringBuffer();
        _renderInline(el.nodes, inner);
        final text = inner.toString().trim();
        if (text.isNotEmpty && href.isNotEmpty) {
          buf.write('[$text](${_escapeUrl(href)})');
        } else if (href.isNotEmpty) {
          buf.write(href);
        } else {
          buf.write(text);
        }
        return;

      case 'pre':
        _newline(buf);
        _renderCodeBlock(el, buf);
        _newline(buf);
        return;

      case 'code':
        if (el.parent?.localName == 'pre') return;
        final code = el.text;
        buf.write('`${code.replaceAll('`', '\\`')}`');
        return;

      case 'strong':
      case 'b':
        buf.write('**');
        _renderInline(el.nodes, buf);
        buf.write('**');
        return;

      case 'em':
      case 'i':
        buf.write('*');
        _renderInline(el.nodes, buf);
        buf.write('*');
        return;

      case 'span':
        _renderInline(el.nodes, buf);
        return;

      case 'table':
        _newline(buf);
        _renderTable(el, buf);
        _newline(buf);
        return;

      case 'tr':
      case 'td':
      case 'th':
      case 'thead':
      case 'tbody':
      case 'tfoot':
      case 'caption':
        return;

      default:
        _renderInline(el.nodes, buf);
    }
  }

  static void _renderInline(List<dom.Node> nodes, StringBuffer buf) {
    for (final node in nodes) {
      if (node is dom.Text) {
        buf.write(_escapeMd(node.text));
      } else if (node is dom.Element) {
        _renderElement(node, buf);
      }
    }
  }

  static void _renderBlockquote(List<dom.Node> nodes, StringBuffer buf) {
    for (final node in nodes) {
      if (node is dom.Element && node.localName == 'p') {
        final inner = StringBuffer();
        _renderInline(node.nodes, inner);
        final text = inner.toString().trim();
        if (text.isNotEmpty) {
          buf.writeln('> $text');
        }
      } else if (node is dom.Element && node.localName == 'blockquote') {
        final inner = StringBuffer();
        _renderBlockquote(node.nodes, inner);
        final lines = inner.toString().trim().split('\n');
        for (final line in lines) {
          if (line.trim().isNotEmpty) {
            buf.writeln('> > ${line.trim()}');
          }
        }
      } else if (node is dom.Text) {
        final text = _escapeMd(node.text.trim());
        if (text.isNotEmpty) {
          buf.writeln('> $text');
        }
      } else {
        _renderBlockquote(node is dom.Element ? node.nodes : [node], buf);
      }
    }
  }

  static void _renderList(List<dom.Node> nodes, StringBuffer buf, {required bool ordered, int indent = 0}) {
    int counter = 1;
    for (final node in nodes) {
      if (node is! dom.Element) continue;
      if (node.localName != 'li') continue;

      final prefix = ordered ? '$counter.' : '-';
      final indentStr = '  ' * indent;
      buf.write('$indentStr$prefix ');

      final innerBuf = StringBuffer();
      for (final child in node.nodes) {
        if (child is dom.Element && (child.localName == 'ul' || child.localName == 'ol')) {
          final nested = StringBuffer();
          _renderList(child.nodes, nested,
              ordered: child.localName == 'ol', indent: indent + 1);
          final nestedStr = nested.toString().trim();
          if (nestedStr.isNotEmpty) {
            buf.writeln();
            buf.write(nestedStr);
            buf.writeln();
          }
        } else if (child is dom.Element && child.localName == 'p') {
          final pBuf = StringBuffer();
          _renderInline(child.nodes, pBuf);
          final text = pBuf.toString().trim();
          if (text.isNotEmpty) {
            buf.write(text);
            buf.writeln();
            buf.write('$indentStr  ');
          }
        } else if (child is dom.Element) {
          _renderElement(child, innerBuf);
        } else if (child is dom.Text) {
          innerBuf.write(_escapeMd(child.text));
        }
      }
      final innerText = innerBuf.toString().trim();
      if (innerText.isNotEmpty) {
        buf.write(innerText);
      }
      buf.writeln();
      if (ordered) counter++;
    }
  }

  static void _renderCodeBlock(dom.Element el, StringBuffer buf) {
    String? lang;
    String code;

    final codeEl = el.querySelector('code');
    if (codeEl != null) {
      code = codeEl.text;
      lang = codeEl.attributes['class'] ?? '';
      if (lang.startsWith('language-')) {
        lang = lang.substring(9);
      } else {
        lang = '';
      }
    } else {
      code = el.text;
      lang = '';
    }

    code = code.replaceAll('```', '\\`\\`\\`');
    buf.writeln('```$lang');
    buf.writeln(code.trim());
    buf.writeln('```');
  }

  static void _renderTable(dom.Element el, StringBuffer buf) {
    final rows = el.querySelectorAll('tr');
    if (rows.isEmpty) return;

    for (final row in rows) {
      final cells = row.querySelectorAll('th, td');
      for (var i = 0; i < cells.length; i++) {
        if (i > 0) buf.write(' | ');
        buf.write(_escapeMd(cells[i].text.trim()));
      }
      buf.writeln();
    }
  }

  static String _escapeMd(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('*', '\\*')
        .replaceAll('_', '\\_')
        .replaceAll('`', '\\`')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        .replaceAll('(', '\\(')
        .replaceAll(')', '\\)')
        .replaceAll('#', '\\#')
        .replaceAll('-', '\\-')
        .replaceAll('!', '\\!');
  }

  static String _escapeUrl(String url) {
    return url
        .replaceAll('(', '%28')
        .replaceAll(')', '%29')
        .replaceAll(' ', '%20');
  }

  static void _newline(StringBuffer buf) {
    if (buf.isNotEmpty && !buf.toString().endsWith('\n')) {
      buf.writeln();
    }
  }
}
