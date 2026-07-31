/// One TTS chunk: a piece of a display paragraph that is synthesized and
/// played as a unit.
class TtsChunk {
  /// Flat index in the chunk list.
  final int index;

  /// Display paragraph this chunk belongs to (scroll/highlight sync).
  final int paragraphIndex;

  /// Char offset of the chunk start in the paragraph plain text.
  final int startOffset;

  /// Char offset of the chunk end in the paragraph plain text.
  final int endOffset;

  /// Word index of the chunk start inside the paragraph.
  final int paragraphWordOffset;

  /// Number of sentences fully contained in this chunk.
  final int sentenceCount;

  /// Estimated playback duration (`length / charsPerSecond / speed`).
  final int estimatedDurationMs;

  final String text;

  const TtsChunk({
    required this.index,
    required this.paragraphIndex,
    required this.startOffset,
    required this.endOffset,
    required this.paragraphWordOffset,
    required this.sentenceCount,
    required this.estimatedDurationMs,
    required this.text,
  });
}

/// A text segment within a paragraph, with char offsets relative to the
/// (trimmed) paragraph text.
class _Unit {
  final String text;
  final int start;
  final int end;

  const _Unit(this.text, this.start, this.end);

  int get length => text.length;
}

/// Splits paragraphs into TTS chunks.
///
/// Algorithm per paragraph:
/// 1. Whole paragraph within `targetMs` → one chunk.
/// 2. Otherwise split at sentence boundaries, greedily packing sentences
///    until `softMaxMs`.
/// 3. A single sentence over the soft max splits at clause boundaries.
/// 4. Last resort: hard split at `hardMaxChars`, breaking at the last space
///    (never mid-word for latin text).
class TtsChunker {
  /// Preferred chunk duration.
  final int targetMs;

  /// Hard ceiling per chunk (sentence-packed).
  final int softMaxMs;

  /// Absolute character ceiling per chunk.
  final int hardMaxChars;

  /// Speaking rate heuristic for duration estimates.
  final int charsPerSecond;

  const TtsChunker({
    this.targetMs = 15000,
    this.softMaxMs = 20000,
    this.hardMaxChars = 2000,
    this.charsPerSecond = 15,
  });

  static final RegExp _sentenceEnd = RegExp(r'[.!?。！？]');
  static final RegExp _clauseEnd = RegExp(r'[,;:—–-、，；：]');
  static final RegExp _wordSeparator = RegExp(r'\s+');

  int _charBudget(int ms) => (ms * charsPerSecond / 1000).round();

  /// Chunks a list of paragraphs. Empty paragraphs produce no chunks.
  List<TtsChunk> chunkParagraphs(
    List<String> paragraphs, {
    double speed = 1.0,
  }) {
    final chunks = <TtsChunk>[];
    for (var pi = 0; pi < paragraphs.length; pi++) {
      final text = paragraphs[pi].trim();
      if (text.isEmpty) continue;
      _chunkParagraph(text, pi, speed, chunks);
    }
    return chunks;
  }

  void _chunkParagraph(
    String paragraph,
    int paragraphIndex,
    double speed,
    List<TtsChunk> out,
  ) {
    final targetChars = _charBudget(targetMs);
    final softMaxChars = _charBudget(softMaxMs);

    if (paragraph.length <= targetChars) {
      out.add(_buildChunk(
        _Unit(paragraph, 0, paragraph.length),
        paragraph,
        paragraphIndex,
        speed,
        sentenceCount: _countSentences(paragraph),
        out: out,
      ));
      return;
    }

    final units = _splitSentences(paragraph);
    var start = 0;
    while (start < units.length) {
      if (units[start].length > softMaxChars) {
        for (final part in _splitOversizeUnit(units[start], softMaxChars)) {
          out.add(_buildChunk(
            part,
            paragraph,
            paragraphIndex,
            speed,
            sentenceCount: 1,
            out: out,
          ));
        }
        start++;
        continue;
      }
      var end = start;
      var length = 0;
      while (end < units.length &&
          length + units[end].length <= softMaxChars) {
        length += units[end].length;
        end++;
      }
      if (end == start) end = start + 1;

      final merged = units.sublist(start, end);
      out.add(_buildChunk(
        _Unit(
          merged.map((u) => u.text).join(),
          merged.first.start,
          merged.last.end,
        ),
        paragraph,
        paragraphIndex,
        speed,
        sentenceCount: merged.length,
        out: out,
      ));
      start = end;
    }
  }

  /// Splits [text] at sentence-ending punctuation. Latin `.?!` only end a
  /// sentence when followed by whitespace or end of text; CJK `。！？` always
  /// end a sentence. Punctuation stays attached to its sentence.
  List<_Unit> _splitSentences(String text) {
    final units = <_Unit>[];
    var start = 0;
    for (final match in _sentenceEnd.allMatches(text)) {
      final after = match.end;
      final punct = text[match.start];
      if (punct != '。' &&
          punct != '！' &&
          punct != '？' &&
          after < text.length &&
          !_isWhitespace(text[after])) {
        continue;
      }
      units.add(_Unit(text.substring(start, after), start, after));
      start = after;
    }
    if (start < text.length) {
      units.add(_Unit(text.substring(start), start, text.length));
    }
    return units;
  }

  /// Splits an oversize sentence: greedily packed clauses, then hard splits.
  List<_Unit> _splitOversizeUnit(_Unit unit, int softMaxChars) {
    final clauses = <_Unit>[];
    var start = 0;
    for (final match in _clauseEnd.allMatches(unit.text)) {
      final after = match.end;
      if (after >= unit.text.length) continue;
      clauses.add(
        _Unit(unit.text.substring(start, after), unit.start + start, unit.start + after),
      );
      start = after;
    }
    if (start < unit.text.length) {
      clauses.add(
        _Unit(unit.text.substring(start), unit.start + start, unit.start + unit.text.length),
      );
    }

    final result = <_Unit>[];
    var buffer = <_Unit>[];
    var bufferLength = 0;

    void flush() {
      if (buffer.isEmpty) return;
      result.add(_Unit(
        buffer.map((u) => u.text).join(),
        buffer.first.start,
        buffer.last.end,
      ));
      buffer = [];
      bufferLength = 0;
    }

    for (final clause in clauses) {
      if (clause.length > softMaxChars) {
        flush();
        result.addAll(_hardSplit(clause));
      } else if (bufferLength + clause.length > softMaxChars && buffer.isNotEmpty) {
        flush();
        buffer.add(clause);
        bufferLength = clause.length;
      } else {
        buffer.add(clause);
        bufferLength += clause.length;
      }
    }
    flush();
    return result;
  }

  /// Hard splits at [hardMaxChars], breaking at the last space/newline in the
  /// window (anywhere for CJK text with no spaces).
  List<_Unit> _hardSplit(_Unit unit) {
    final pieces = <_Unit>[];
    var pos = 0;
    while (unit.length - pos > hardMaxChars) {
      var cut = pos + hardMaxChars;
      final window = unit.text.substring(pos, cut);
      final lastSpace =
          _maxIndex(window.lastIndexOf(' '), window.lastIndexOf('\n'));
      if (lastSpace > 0) cut = pos + lastSpace + 1;
      pieces.add(
        _Unit(unit.text.substring(pos, cut), unit.start + pos, unit.start + cut),
      );
      pos = cut;
      while (pos < unit.length && unit.text[pos] == ' ') {
        pos++;
      }
    }
    if (pos < unit.length) {
      pieces.add(
        _Unit(unit.text.substring(pos), unit.start + pos, unit.start + unit.length),
      );
    }
    return pieces;
  }

  TtsChunk _buildChunk(
    _Unit unit,
    String paragraph,
    int paragraphIndex,
    double speed, {
    required int sentenceCount,
    required List<TtsChunk> out,
  }) {
    return TtsChunk(
      index: out.length,
      paragraphIndex: paragraphIndex,
      startOffset: unit.start,
      endOffset: unit.end,
      paragraphWordOffset: _countWords(paragraph.substring(0, unit.start)),
      sentenceCount: sentenceCount,
      estimatedDurationMs:
          (unit.length / charsPerSecond / speed * 1000).round(),
      text: unit.text,
    );
  }

  static int _countWords(String text) {
    if (text.isEmpty) return 0;
    return _wordSeparator.allMatches(text).length + 1;
  }

  static int _maxIndex(int a, int b) => a > b ? a : b;

  static bool _isWhitespace(String char) =>
      char == ' ' || char == '\t' || char == '\n' || char == '\r';

  static int _countSentences(String text) {
    var count = 0;
    for (final match in _sentenceEnd.allMatches(text)) {
      final after = match.end;
      final punct = text[match.start];
      if (punct != '。' &&
          punct != '！' &&
          punct != '？' &&
          after < text.length &&
          !_isWhitespace(text[after])) {
        continue;
      }
      count++;
    }
    return count;
  }
}
