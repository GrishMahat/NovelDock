import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/database/database.dart';
import 'package:noveldock/features/novel/chapter_sort.dart';

Chapter _chapter(String name, double index) => Chapter(
  id: index.toInt(),
  novelId: 1,
  name: name,
  url: 'c$index',
  index: index,
  downloaded: false,
  read: false,
  ttsRead: false,
  bookmarked: false,
  downloadedPath: null,
);

void main() {
  group('parseChapterNumber', () {
    test('marker-prefixed numbers', () {
      expect(parseChapterNumber('Chapter 12: Dawn'), 12);
      expect(parseChapterNumber('Ch.3 - Dusk'), 3);
      expect(parseChapterNumber('EP 7'), 7);
      expect(parseChapterNumber('Episode 2.5 (part 1)'), 2.5);
      expect(parseChapterNumber('#42'), 42);
    });

    test('falls back to the first bare number', () {
      expect(parseChapterNumber('12 - Dawn'), 12);
      expect(parseChapterNumber('Vol 2 Chapter 5'), 5);
    });

    test('unnumbered titles yield null', () {
      expect(parseChapterNumber('Prologue'), isNull);
      expect(parseChapterNumber('Side Story: The Inn'), isNull);
    });
  });

  group('sortChapters', () {
    // Provider listing is newest-first here: numeric sort must still
    // recover reading order, which lexicographic sort cannot.
    final jumbled = [
      _chapter('Chapter 10', 0),
      _chapter('Chapter 2', 1),
      _chapter('Prologue', 2),
      _chapter('Chapter 1', 3),
    ];

    test('normal follows provider order', () {
      final names = sortChapters(
        jumbled,
        ChapterSort.normal,
      ).map((c) => c.name);
      expect(names, ['Chapter 10', 'Chapter 2', 'Prologue', 'Chapter 1']);
    });

    test('number sorts numerically, unnumbered last', () {
      final names = sortChapters(
        jumbled,
        ChapterSort.number,
      ).map((c) => c.name);
      expect(names, ['Chapter 1', 'Chapter 2', 'Chapter 10', 'Prologue']);
    });

    test('latest reverses provider order', () {
      final names = sortChapters(
        jumbled,
        ChapterSort.latest,
      ).map((c) => c.name);
      expect(names, ['Chapter 1', 'Prologue', 'Chapter 2', 'Chapter 10']);
    });

    test('does not mutate the input list', () {
      final input = List.of(jumbled);
      sortChapters(input, ChapterSort.number);
      expect(input.map((c) => c.name), [
        'Chapter 10',
        'Chapter 2',
        'Prologue',
        'Chapter 1',
      ]);
    });
  });
}
