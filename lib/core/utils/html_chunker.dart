class HtmlChunk {
  final int index;
  final String rawHtml;
  final String plainText;
  final List<String> sentences;

  const HtmlChunk({
    required this.index,
    required this.rawHtml,
    required this.plainText,
    required this.sentences,
  });
}

class HtmlChunker {
  /// Parses HTML into paragraph/block chunks and extracts plain text sentences for TTS.
  static List<HtmlChunk> chunkHtml(String html) {
    if (html.trim().isEmpty) return [];

    final rawChunks = <String>[];

    // Match block tags (<p>, <div>, <h1>-<h6>, blockquote, li, tr)
    final blockRegExp = RegExp(
      r'<(p|div|h[1-6]|blockquote|li|tr)\b[^>]*>.*?</\1>',
      caseSensitive: false,
      dotAll: true,
    );

    final matches = blockRegExp.allMatches(html).toList();

    if (matches.isNotEmpty) {
      for (final m in matches) {
        final blockHtml = m.group(0)?.trim() ?? '';
        if (blockHtml.isNotEmpty) {
          rawChunks.add(blockHtml);
        }
      }
    } else {
      // Fallback if no block tags: split by double newlines or single newlines
      final parts = html.split(RegExp(r'\n\s*\n|\n'));
      for (final p in parts) {
        final trimmed = p.trim();
        if (trimmed.isNotEmpty) {
          rawChunks.add('<p>$trimmed</p>');
        }
      }
    }

    if (rawChunks.isEmpty) {
      rawChunks.add('<p>${html.trim()}</p>');
    }

    final result = <HtmlChunk>[];
    for (int i = 0; i < rawChunks.length; i++) {
      final chunkHtml = rawChunks[i];
      final plainText = _extractPlainText(chunkHtml);
      final sentences = _extractSentences(plainText);

      result.add(HtmlChunk(
        index: i,
        rawHtml: chunkHtml,
        plainText: plainText,
        sentences: sentences,
      ));
    }

    return result;
  }

  static String _extractPlainText(String html) {
    // Decode common HTML entities
    final decoded = html
        .replaceAll('&ldquo;', '\u201C').replaceAll('&rdquo;', '\u201D')
        .replaceAll('&lsquo;', '\u2018').replaceAll('&rsquo;', '\u2019')
        .replaceAll('&mdash;', '\u2014').replaceAll('&ndash;', '\u2013')
        .replaceAll('&hellip;', '\u2026').replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"').replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ').replaceAll('&#160;', ' ');

    return decoded.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> _extractSentences(String text) {
    if (text.isEmpty) return [];
    final sentences = <String>[];

    for (var s in text.split(RegExp(r'(?<=[.!?])\s+'))) {
      final trimmed = s.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.length > 300) {
        final subParts = trimmed.split(RegExp(r'(?<=[,;])\s+'));
        String buffer = '';
        for (final part in subParts) {
          if (buffer.length + part.length > 280) {
            if (buffer.isNotEmpty) sentences.add(buffer.trim());
            buffer = part;
          } else {
            buffer = buffer.isEmpty ? part : '$buffer $part';
          }
        }
        if (buffer.isNotEmpty) sentences.add(buffer.trim());
      } else {
        sentences.add(trimmed);
      }
    }

    return sentences;
  }
}
