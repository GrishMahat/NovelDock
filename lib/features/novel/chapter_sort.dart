import '../../core/database/database.dart';

/// Chapter list order. Deliberately three modes, no alphabetic sort:
/// lexicographic order puts "Chapter 10" before "Chapter 2", which is
/// never what a reader wants.
enum ChapterSort {
  /// Provider listing order, oldest first.
  normal,

  /// Numeric chapter number ascending ("Chapter 2" before "Chapter 10"),
  /// even when the provider lists newest-first or jumbled. Unnumbered
  /// chapters keep provider order at the end.
  number,

  /// Newest uploads first (reverse provider order). Per-chapter upload
  /// dates would be ideal, but providers don't supply them (chapter
  /// `date` is null in practice), so reverse listing is the honest
  /// approximation.
  latest,
}

extension ChapterSortLabel on ChapterSort {
  String get label => switch (this) {
    ChapterSort.normal => 'Normal',
    ChapterSort.number => 'Chapter number',
    ChapterSort.latest => 'Latest first',
  };
}

/// First chapter number found in [name]: prefers an explicit marker
/// (chapter/ch/episode/ep/part/#), falls back to the first bare number.
/// Returns null when the title carries no number at all.
double? parseChapterNumber(String name) {
  final marker = RegExp(
    r'(?:chapter|chap|ch\.?|episode|ep\.?|part|#)\s*\.?\s*(\d+(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(name);
  if (marker != null) return double.tryParse(marker.group(1)!);
  final bare = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(name);
  if (bare != null) return double.tryParse(bare.group(1)!);
  return null;
}

/// Returns a sorted copy; the input list is never mutated.
List<Chapter> sortChapters(List<Chapter> chapters, ChapterSort sort) {
  final sorted = List<Chapter>.from(chapters);
  switch (sort) {
    case ChapterSort.normal:
      sorted.sort((a, b) => a.index.compareTo(b.index));
    case ChapterSort.number:
      sorted.sort((a, b) {
        final na = parseChapterNumber(a.name);
        final nb = parseChapterNumber(b.name);
        if (na == null && nb == null) return a.index.compareTo(b.index);
        if (na == null) return 1;
        if (nb == null) return -1;
        final cmp = na.compareTo(nb);
        return cmp != 0 ? cmp : a.index.compareTo(b.index);
      });
    case ChapterSort.latest:
      sorted.sort((a, b) => b.index.compareTo(a.index));
  }
  return sorted;
}
