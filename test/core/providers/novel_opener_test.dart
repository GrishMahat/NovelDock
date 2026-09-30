import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/providers/novel_opener.dart';

// Pins the chapter-API book id parsing: the id is the last non-empty path
// segment minus extension/query/fragment. A trailing slash must not yield
// an empty id (that silently disables the chapter-API fallback and leaves
// the novel with zero chapters and no error).
void main() {
  group('bookIdFromNovelUrl', () {
    test('plain slug', () {
      expect(
        bookIdFromNovelUrl('https://example.com/novel/my-novel'),
        'my-novel',
      );
    });

    test('trailing slash keeps the slug', () {
      expect(
        bookIdFromNovelUrl('https://example.com/novel/my-novel/'),
        'my-novel',
      );
    });

    test('strips .html extension', () {
      expect(
        bookIdFromNovelUrl('https://example.com/novel/my-novel.html'),
        'my-novel',
      );
    });

    test('strips query and fragment', () {
      expect(
        bookIdFromNovelUrl('https://example.com/novel/my-novel.html?x=1#top'),
        'my-novel',
      );
    });

    test('numeric id segment', () {
      expect(
        bookIdFromNovelUrl('https://www.scribblehub.com/series/12345/slug/'),
        'slug',
      );
    });

    test('empty and root urls yield empty id', () {
      expect(bookIdFromNovelUrl(''), '');
      expect(bookIdFromNovelUrl('https://example.com/'), '');
    });
  });
}
