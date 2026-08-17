/// One TTS chunk: a piece of a display paragraph that is synthesized and
/// played as a unit.
class TtsChunk {
  /// Flat index in the chunk list.
  final int index;

  /// Display paragraph this chunk belongs to.
  final int paragraphIndex;

  /// Character offset of the chunk start in the trimmed paragraph text.
  final int startOffset;

  /// Character offset of the chunk end in the trimmed paragraph text.
  final int endOffset;

  /// Word index of the chunk start inside the paragraph.
  final int paragraphWordOffset;

  /// Number of sentences represented by this chunk.
  final int sentenceCount;

  /// Estimated playback duration in milliseconds.
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

/// A text segment within a paragraph.
///
/// Offsets are relative to the trimmed paragraph text.
class _Unit {
  final String text;
  final int start;
  final int end;

  const _Unit(this.text, this.start, this.end);

  int get length => text.length;
}

/// Splits paragraphs into TTS chunks.
///
/// Strategy:
///
/// 1. Paragraphs under the target size become one chunk.
/// 2. Larger paragraphs are split at sentence boundaries.
/// 3. Sentences are greedily packed up to the soft maximum.
/// 4. An oversized sentence is split at clause boundaries.
/// 5. Oversized clauses are hard-split at a word boundary.
/// 6. CJK/non-whitespace text is allowed to split at the hard character
///    boundary as a final fallback.
///
/// The chunker's offsets always refer to the trimmed paragraph text used for
/// synthesis.
class TtsChunker {
  /// Preferred chunk duration.
  final int targetMs;

  /// Soft maximum chunk duration.
  final int softMaxMs;

  /// Absolute character ceiling per chunk.
  final int hardMaxChars;

  /// Speaking-rate heuristic used for duration estimation.
  final int charsPerSecond;

  const TtsChunker({
    this.targetMs = 15000,
    this.softMaxMs = 20000,
    this.hardMaxChars = 2000,
    this.charsPerSecond = 15,
  }) : assert(targetMs > 0),
       assert(softMaxMs >= targetMs),
       assert(hardMaxChars > 0),
       assert(charsPerSecond > 0);

  static final RegExp _sentenceEnd = RegExp(r'[.!?。！？]');

  static final RegExp _clauseEnd = RegExp(r'[,;:—–\-、，；：]');

  static final RegExp _wordSeparator = RegExp(r'\s+');

  int _charBudget(int milliseconds) {
    return (milliseconds * charsPerSecond / 1000).round().clamp(
      1,
      hardMaxChars,
    );
  }

  /// Chunks all non-empty paragraphs.
  ///
  /// Empty/whitespace-only paragraphs intentionally produce no TTS chunks.
  List<TtsChunk> chunkParagraphs(
    List<String> paragraphs, {
    double speed = 1.0,
  }) {
    final chunks = <TtsChunk>[];

    final safeSpeed = speed > 0 ? speed : 1.0;

    for (
      var paragraphIndex = 0;
      paragraphIndex < paragraphs.length;
      paragraphIndex++
    ) {
      final paragraph = paragraphs[paragraphIndex].trim();

      if (paragraph.isEmpty) continue;

      _chunkParagraph(paragraph, paragraphIndex, safeSpeed, chunks);
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
      out.add(
        _buildChunk(
          _Unit(paragraph, 0, paragraph.length),
          paragraphIndex,
          speed,
          sentenceCount: _countSentences(paragraph),
          out: out,
        ),
      );
      return;
    }

    final sentences = _splitSentences(paragraph);

    // Defensive fallback. A non-empty paragraph should always produce at
    // least one unit, but keeping this explicit avoids an infinite loop if the
    // splitter is ever changed.
    if (sentences.isEmpty) {
      for (final part in _hardSplit(_Unit(paragraph, 0, paragraph.length))) {
        out.add(
          _buildChunk(part, paragraphIndex, speed, sentenceCount: 1, out: out),
        );
      }

      return;
    }

    var start = 0;

    while (start < sentences.length) {
      final current = sentences[start];

      if (current.length > softMaxChars) {
        final parts = _splitOversizeUnit(current, softMaxChars);

        for (final part in parts) {
          out.add(
            _buildChunk(
              part,
              paragraphIndex,
              speed,
              sentenceCount: 1,
              out: out,
            ),
          );
        }

        start++;
        continue;
      }

      var end = start;
      var length = 0;

      while (end < sentences.length &&
          length + sentences[end].length <= softMaxChars) {
        length += sentences[end].length;
        end++;
      }

      // At least one sentence must be consumed.
      if (end == start) {
        end = start + 1;
      }

      final merged = sentences.sublist(start, end);

      out.add(
        _buildChunk(
          _Unit(
            merged.map((unit) => unit.text).join(),
            merged.first.start,
            merged.last.end,
          ),
          paragraphIndex,
          speed,
          sentenceCount: merged.length,
          out: out,
        ),
      );

      start = end;
    }
  }

  /// Splits a paragraph at sentence-ending punctuation.
  ///
  /// For Latin punctuation, `.`, `!`, and `?` are treated as sentence
  /// endings only when followed by whitespace or the end of the text.
  ///
  /// CJK sentence punctuation always terminates a sentence.
  List<_Unit> _splitSentences(String text) {
    final units = <_Unit>[];

    var start = 0;

    for (final match in _sentenceEnd.allMatches(text)) {
      final punctuation = text[match.start];

      final after = match.end;

      final isCjkEnd =
          punctuation == '。' || punctuation == '！' || punctuation == '？';

      if (!isCjkEnd &&
          after < text.length &&
          !_isWhitespace(text.codeUnitAt(after))) {
        continue;
      }

      final end = after;

      if (end <= start) continue;

      units.add(_Unit(text.substring(start, end), start, end));

      start = end;

      // Include immediate whitespace in the current sentence so the merged
      // chunks preserve the original paragraph exactly.
      while (start < text.length && _isWhitespace(text.codeUnitAt(start))) {
        start++;
      }
    }

    if (start < text.length) {
      units.add(_Unit(text.substring(start), start, text.length));
    }

    return units;
  }

  /// Splits a sentence that is larger than the soft limit.
  ///
  /// Clause boundaries are preferred. Any clause that is still too large is
  /// passed through the hard splitter.
  List<_Unit> _splitOversizeUnit(_Unit unit, int softMaxChars) {
    final clauses = _splitClauses(unit);

    if (clauses.length == 1 && clauses.first.length > softMaxChars) {
      return _hardSplit(clauses.first);
    }

    final result = <_Unit>[];

    var buffer = <_Unit>[];
    var bufferLength = 0;

    void flush() {
      if (buffer.isEmpty) return;

      result.add(
        _Unit(
          buffer.map((part) => part.text).join(),
          buffer.first.start,
          buffer.last.end,
        ),
      );

      buffer = <_Unit>[];
      bufferLength = 0;
    }

    for (final clause in clauses) {
      if (clause.length > softMaxChars) {
        flush();
        result.addAll(_hardSplit(clause));
        continue;
      }

      if (buffer.isNotEmpty && bufferLength + clause.length > softMaxChars) {
        flush();
      }

      buffer.add(clause);
      bufferLength += clause.length;
    }

    flush();

    return result;
  }

  List<_Unit> _splitClauses(_Unit unit) {
    final clauses = <_Unit>[];

    var start = 0;

    for (final match in _clauseEnd.allMatches(unit.text)) {
      final end = match.end;

      if (end >= unit.text.length) {
        continue;
      }

      clauses.add(
        _Unit(
          unit.text.substring(start, end),
          unit.start + start,
          unit.start + end,
        ),
      );

      start = end;

      // Keep whitespace with the preceding clause.
      while (start < unit.text.length &&
          _isWhitespace(unit.text.codeUnitAt(start))) {
        start++;
      }
    }

    if (start < unit.text.length) {
      clauses.add(
        _Unit(unit.text.substring(start), unit.start + start, unit.end),
      );
    }

    if (clauses.isEmpty) {
      return <_Unit>[unit];
    }

    return clauses;
  }

  /// Hard-splits a unit at approximately [hardMaxChars].
  ///
  /// A nearby whitespace boundary is preferred for Latin text. When there is
  /// no suitable whitespace, the split occurs at the hard character limit,
  /// which is necessary for languages that do not use spaces.
  List<_Unit> _hardSplit(_Unit unit) {
    if (unit.length <= hardMaxChars) {
      return <_Unit>[unit];
    }

    final pieces = <_Unit>[];

    var position = 0;

    while (unit.length - position > hardMaxChars) {
      final desiredCut = position + hardMaxChars;

      final window = unit.text.substring(position, desiredCut);

      final lastWhitespace = _lastWhitespaceIndex(window);

      var cut = desiredCut;

      // Don't create a tiny fragment merely to save one whitespace.
      if (lastWhitespace > 0) {
        final whitespaceCut = position + lastWhitespace;

        final pieceLength = whitespaceCut - position;

        if (pieceLength >= (hardMaxChars * 0.65).floor()) {
          cut = whitespaceCut;
        }
      }

      // Ensure forward progress.
      if (cut <= position) {
        cut = desiredCut;
      }

      pieces.add(
        _Unit(
          unit.text.substring(position, cut),
          unit.start + position,
          unit.start + cut,
        ),
      );

      position = cut;

      // Discard only whitespace that sits at the split boundary. This keeps
      // the spoken text natural while preserving valid offsets for the next
      // unit.
      while (position < unit.length &&
          _isWhitespace(unit.text.codeUnitAt(position))) {
        position++;
      }
    }

    if (position < unit.length) {
      pieces.add(
        _Unit(unit.text.substring(position), unit.start + position, unit.end),
      );
    }

    return pieces;
  }

  TtsChunk _buildChunk(
    _Unit unit,
    int paragraphIndex,
    double speed, {
    required int sentenceCount,
    required List<TtsChunk> out,
  }) {
    final estimatedDurationMs = (unit.length / charsPerSecond / speed * 1000)
        .round()
        .clamp(1, 0x7fffffff);

    return TtsChunk(
      index: out.length,
      paragraphIndex: paragraphIndex,
      startOffset: unit.start,
      endOffset: unit.end,
      paragraphWordOffset: _countWordsBeforeOffset(unit.text, 0),
      sentenceCount: sentenceCount.clamp(0, 0x7fffffff),
      estimatedDurationMs: estimatedDurationMs,
      text: unit.text,
    );
  }

  /// Counts words before an offset.
  ///
  /// This is intentionally based on the chunk's text here because the chunk
  /// builder receives only the local unit. The public chunk offset remains
  /// paragraph-relative.
  ///
  /// For exact paragraph-level highlighting the controller/engine should use
  /// the engine's actual boundary offsets rather than relying solely on this
  /// estimated word position.
  static int _countWordsBeforeOffset(String text, int offset) {
    if (text.isEmpty || offset <= 0) {
      return 0;
    }

    final safeOffset = offset.clamp(0, text.length);

    final prefix = text.substring(0, safeOffset);

    return _countWords(prefix);
  }

  static int _countWords(String text) {
    final trimmed = text.trim();

    if (trimmed.isEmpty) {
      return 0;
    }

    return _wordSeparator.allMatches(trimmed).length + 1;
  }

  static int _countSentences(String text) {
    var count = 0;

    for (final match in _sentenceEnd.allMatches(text)) {
      final punctuation = text[match.start];

      final after = match.end;

      final isCjkEnd =
          punctuation == '。' || punctuation == '！' || punctuation == '？';

      if (isCjkEnd ||
          after >= text.length ||
          _isWhitespace(text.codeUnitAt(after))) {
        count++;
      }
    }

    return count;
  }

  static int _lastWhitespaceIndex(String text) {
    for (var i = text.length - 1; i >= 0; i--) {
      if (_isWhitespace(text.codeUnitAt(i))) {
        return i;
      }
    }

    return -1;
  }

  static bool _isWhitespace(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D ||
        codeUnit == 0x0B ||
        codeUnit == 0x0C;
  }
}
