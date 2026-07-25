import 'tts_manager.dart';

class _PlainMapping {
  final String plainText;
  final List<int> htmlIndices;

  _PlainMapping(this.plainText, this.htmlIndices);

  static _PlainMapping build(String html) {
    final plainBuf = StringBuffer();
    final indices = <int>[];
    bool inTag = false;

    for (int i = 0; i < html.length; i++) {
      final c = html[i];

      if (c == '<') {
        inTag = true;
        continue;
      }
      if (inTag) {
        if (c == '>') {
          inTag = false;
          final lastOpen = html.lastIndexOf('<', i);
          final tagContent = html.substring(lastOpen < 0 ? 0 : lastOpen, i + 1).toLowerCase();
          final isBlock = tagContent.contains(
            RegExp(r'</?(?:p|br|div|h[1-6]|li|blockquote|tr|td|th|ul|ol|table|section|article|header|footer)\b'),
          );
          if (isBlock) {
            if (plainBuf.isNotEmpty && !plainBuf.toString().endsWith(' ')) {
              plainBuf.write(' ');
              indices.add(i + 1);
            }
          }
        }
        continue;
      }

      // Entity
      if (c == '&' && i + 1 < html.length) {
        final semi = html.indexOf(';', i);
        if (semi > i && semi < i + 10) {
          final entity = html.substring(i, semi + 1);
          final decoded = _decodeEntity(entity);
          if (decoded.trim().isEmpty || decoded == ' ') {
            if (plainBuf.isNotEmpty && !plainBuf.toString().endsWith(' ')) {
              plainBuf.write(' ');
              indices.add(i);
            }
          } else {
            for (int k = 0; k < decoded.length; k++) {
              plainBuf.write(decoded[k]);
              indices.add(i);
            }
          }
          i = semi;
          continue;
        }
      }

      // Whitespace (including non-breaking spaces & unicode spaces)
      if (c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '\u00A0' || c == '\uFEFF' || c.codeUnitAt(0) == 160) {
        if (plainBuf.isNotEmpty && !plainBuf.toString().endsWith(' ')) {
          plainBuf.write(' ');
          indices.add(i);
        }
        continue;
      }

      // Normal character
      plainBuf.write(c);
      indices.add(i);
    }

    return _PlainMapping(plainBuf.toString(), indices);
  }

  static String _decodeEntity(String entity) {
    switch (entity.toLowerCase()) {
      case '&amp;': return '&';
      case '&lt;': return '<';
      case '&gt;': return '>';
      case '&quot;': return '"';
      case '&apos;': return "'";
      case '&nbsp;': return ' ';
      case '&#160;': return ' ';
      case '&#xa0;': return ' ';
      default:
        if (entity.startsWith('&#x') || entity.startsWith('&#X')) {
          final code = int.tryParse(entity.substring(3, entity.length - 1), radix: 16);
          return code != null ? String.fromCharCode(code) : entity;
        } else if (entity.startsWith('&#')) {
          final code = int.tryParse(entity.substring(2, entity.length - 1));
          return code != null ? String.fromCharCode(code) : entity;
        }
        return entity;
    }
  }
}

/// Highlights text in HTML for TTS read-along.
class TtsHighlighter {
  static String highlight(String html, String highlightText, TtsHighlightMode mode, {int wordIndex = 0}) {
    if (highlightText.isEmpty || html.isEmpty) return html;

    switch (mode) {
      case TtsHighlightMode.paragraph:
        return _highlightParagraph(html, highlightText);
      case TtsHighlightMode.sentence:
        return _highlightInline(html, highlightText);
      case TtsHighlightMode.word:
        return _highlightWord(html, highlightText, wordIndex);
    }
  }

  // ─── Range Finder with 1:1 Index Alignment ───

  static (int, int)? _findRangeInPlain(String plainText, String targetText) {
    if (plainText.isEmpty || targetText.isEmpty) return null;

    final normPlain = _normalizeForSearch(plainText);
    final normTarget = _normalizeForSearch(targetText).trim();

    final plainLower = normPlain.toLowerCase();
    final targetLower = normTarget.toLowerCase();

    // 1. Exact match
    var matchStart = plainLower.indexOf(targetLower);
    if (matchStart >= 0) {
      return (matchStart, matchStart + normTarget.length);
    }

    // 2. Partial prefix match (first 25 chars)
    final partialLength = targetLower.length.clamp(0, 25).toInt();
    final partial = targetLower.substring(0, partialLength);
    matchStart = plainLower.indexOf(partial);
    if (matchStart >= 0) {
      final end = (matchStart + normTarget.length).clamp(0, plainText.length);
      return (matchStart, end);
    }

    // 3. Fuzzy word sequence match
    final words = _extractWords(targetLower);
    if (words.isEmpty) return null;

    final firstWord = words.first;
    int searchPos = 0;
    while (searchPos < plainLower.length) {
      final idx = plainLower.indexOf(firstWord, searchPos);
      if (idx < 0) break;

      int lastWordEnd = idx + firstWord.length;
      bool matched = true;
      int currentPlainPos = lastWordEnd;

      for (int w = 1; w < words.length; w++) {
        final wIdx = plainLower.indexOf(words[w], currentPlainPos);
        if (wIdx >= 0 && wIdx - currentPlainPos < 80) {
          lastWordEnd = wIdx + words[w].length;
          currentPlainPos = lastWordEnd;
        } else {
          matched = false;
          break;
        }
      }

      if (matched) {
        return (idx, lastWordEnd.clamp(idx + 1, plainText.length));
      }
      searchPos = idx + 1;
    }

    return null;
  }

  static String _normalizeForSearch(String str) {
    return str
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u2014', '-')
        .replaceAll('\u2013', '-')
        .replaceAll('\u00A0', ' ');
  }

  static List<String> _extractWords(String str) {
    final words = <String>[];
    final matches = RegExp(r'[a-zA-Z0-9\u00C0-\u024F]+').allMatches(str);
    for (final m in matches) {
      final w = m.group(0)!;
      if (w.length >= 2) words.add(w);
    }
    return words;
  }

  // ─── Paragraph Mode ───

  static String _highlightParagraph(String html, String text) {
    final cleanHtml = _removeHighlights(html);
    final mapping = _PlainMapping.build(cleanHtml);
    final range = _findRangeInPlain(mapping.plainText, text);
    if (range == null) return cleanHtml;

    final (plainStart, plainEnd) = range;
    final htmlStart = mapping.htmlIndices[plainStart.clamp(0, mapping.htmlIndices.length - 1)];

    // Locate enclosing <p> tag in cleanHtml
    final pStart = cleanHtml.lastIndexOf(RegExp(r'<p\b[^>]*>', caseSensitive: false), htmlStart);
    if (pStart >= 0) {
      final pEnd = cleanHtml.indexOf('</p>', htmlStart);
      if (pEnd > pStart) {
        final pCloseEnd = pEnd + 4;
        final innerStart = cleanHtml.indexOf('>', pStart) + 1;
        final before = cleanHtml.substring(0, innerStart);
        final inner = cleanHtml.substring(innerStart, pEnd);
        final after = cleanHtml.substring(pCloseEnd);
        return '$before<span class="tts-highlight-paragraph">$inner</span></p>$after';
      }
    }

    return _highlightInline(cleanHtml, text);
  }

  // ─── Sentence Mode ───

  static String _highlightInline(String html, String text) {
    final cleanHtml = _removeHighlights(html);
    final mapping = _PlainMapping.build(cleanHtml);
    final range = _findRangeInPlain(mapping.plainText, text);
    if (range == null) return cleanHtml;

    return _wrapMappingRange(cleanHtml, mapping, range.$1, range.$2, 'tts-highlight-sentence');
  }

  // ─── Word Mode (Parent-Child Nesting) ───

  static String _highlightWord(String html, String text, int wordIndex) {
    final cleanHtml = _removeHighlights(html);
    final mapping = _PlainMapping.build(cleanHtml);
    final range = _findRangeInPlain(mapping.plainText, text);
    if (range == null) return cleanHtml;

    final (matchStart, matchEnd) = range;
    final sentenceWordPositions = _extractWordPositions(text);
    if (sentenceWordPositions.isEmpty) {
      return _wrapMappingRange(cleanHtml, mapping, matchStart, matchEnd, 'tts-highlight-sentence');
    }

    final idx = wordIndex.clamp(0, sentenceWordPositions.length - 1);
    final (relStart, relEnd) = sentenceWordPositions[idx];

    final absWordStart = matchStart + relStart;
    final absWordEnd = matchStart + relEnd;

    // 1. Wrap parent sentence context
    final sentenceWrapped = _wrapMappingRange(
      cleanHtml, mapping, matchStart, matchEnd, 'tts-highlight-sentence',
    );

    // 2. Build mapping for sentenceWrapped to wrap active child word inside
    final wordMapping = _PlainMapping.build(sentenceWrapped);
    return _wrapMappingRange(
      sentenceWrapped, wordMapping, absWordStart, absWordEnd, 'tts-highlight-word',
    );
  }

  static String _wrapMappingRange(
    String html,
    _PlainMapping mapping,
    int plainStart,
    int plainEnd,
    String cssClass,
  ) {
    if (mapping.htmlIndices.isEmpty) return html;

    final safeStart = plainStart.clamp(0, mapping.htmlIndices.length - 1);
    final safeEndIndex = (plainEnd - 1).clamp(0, mapping.htmlIndices.length - 1);

    if (safeStart > safeEndIndex) return html;

    final htmlStart = mapping.htmlIndices[safeStart];
    var htmlEnd = (plainEnd < mapping.htmlIndices.length)
        ? mapping.htmlIndices[plainEnd]
        : html.length;

    if (htmlStart >= htmlEnd) return html;

    // Ensure htmlEnd does not swallow closing block tags like </p>, </div>
    final matchedSub = html.substring(htmlStart, htmlEnd);
    final closingMatch = RegExp(r'</(?:p|div|h[1-6]|li|blockquote|section|article)\b[^>]*>\s*$', caseSensitive: false).firstMatch(matchedSub);
    if (closingMatch != null) {
      htmlEnd -= closingMatch.group(0)!.length;
    }

    if (htmlStart >= htmlEnd) return html;

    final before = html.substring(0, htmlStart);
    final matched = html.substring(htmlStart, htmlEnd);
    final after = html.substring(htmlEnd);

    return '$before<span class="$cssClass">$matched</span>$after';
  }

  // ─── Helpers ───

  static List<(int, int)> _extractWordPositions(String plain) {
    final positions = <(int, int)>[];
    int pos = 0;
    while (pos < plain.length) {
      while (pos < plain.length && !_isWordChar(plain[pos])) {
        pos++;
      }
      if (pos >= plain.length) break;
      int end = pos;
      while (end < plain.length && _isWordChar(plain[end])) {
        end++;
      }
      positions.add((pos, end));
      pos = end;
    }
    return positions;
  }

  static bool _isWordChar(String c) {
    final ch = c.codeUnitAt(0);
    return (ch >= 0x30 && ch <= 0x39) ||
           (ch >= 0x41 && ch <= 0x5A) ||
           (ch >= 0x61 && ch <= 0x7A) ||
           ch >= 0xC0;
  }

  static String _removeHighlights(String html) {
    if (!html.contains('tts-highlight')) return html;
    var clean = html;
    // Iteratively strip innermost tts-highlight spans until all nested levels are removed
    while (clean.contains('tts-highlight')) {
      final prev = clean;
      clean = clean.replaceAllMapped(
        RegExp(r'<span class="tts-highlight[^"]*">((?:(?!<span class="tts-highlight).)*?)</span>', dotAll: true),
        (m) => m.group(1)!,
      );
      if (clean == prev) {
        // Fallback for any orphaned tags
        clean = clean.replaceAll(RegExp(r'</?span\b[^>]*class="tts-highlight[^"]*"[^>]*>', caseSensitive: false), '');
        clean = clean.replaceAll(RegExp(r'<span class="tts-highlight[^"]*">', caseSensitive: false), '');
        break;
      }
    }
    return clean;
  }

  static String _stripTags(String html) {
    final mapping = _PlainMapping.build(html);
    return mapping.plainText;
  }
}
