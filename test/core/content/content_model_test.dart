import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/content/content_model.dart';

void main() {
  group('ContentFormat', () {
    test('has markdown and pdf values', () {
      expect(ContentFormat.values, contains(ContentFormat.markdown));
      expect(ContentFormat.values, contains(ContentFormat.pdf));
    });

    test('markdown is not pdf', () {
      expect(ContentFormat.markdown, isNot(ContentFormat.pdf));
    });
  });

  group('ChapterContent', () {
    test('stores all fields', () {
      final content = ChapterContent(
        format: ContentFormat.markdown,
        data: '# Hello\nWorld',
        chapterId: 42,
      );
      expect(content.format, ContentFormat.markdown);
      expect(content.data, '# Hello\nWorld');
      expect(content.chapterId, 42);
    });

    test('isPdf returns true for pdf format', () {
      final content = ChapterContent(
        format: ContentFormat.pdf,
        data: 'binary-data',
        chapterId: 1,
      );
      expect(content.isPdf, isTrue);
    });

    test('isPdf returns false for markdown format', () {
      final content = ChapterContent(
        format: ContentFormat.markdown,
        data: '# text',
        chapterId: 2,
      );
      expect(content.isPdf, isFalse);
    });

    test('supports const constructor', () {
      const content = ChapterContent(
        format: ContentFormat.markdown,
        data: '',
        chapterId: 0,
      );
      expect(content, isA<ChapterContent>());
    });

    test('accepts empty data', () {
      final content = ChapterContent(
        format: ContentFormat.markdown,
        data: '',
        chapterId: 3,
      );
      expect(content.data, '');
    });
  });
}
