import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/utils/html_preprocessor.dart';

void main() {
  group('HtmlPreprocessor.clean', () {
    test('strips scripts and tracking chrome', () {
      const html =
          '<p>Story</p><script>alert(1)</script>'
          '<nav><a href="/x">menu</a></nav>'
          '<div class="ad-banner">buy this</div>';
      final out = HtmlPreprocessor.clean(html);
      expect(out, contains('Story'));
      expect(out, isNot(contains('alert')));
      expect(out, isNot(contains('menu')));
      expect(out, isNot(contains('buy this')));
    });

    test('strips author notes only when asked', () {
      const html =
          '<p>Story</p>'
          '<div class="qnauthornotecontainer"><p>Author: hi</p></div>'
          '<div class="author-note"><p>Thanks for reading</p></div>';
      final stripped = HtmlPreprocessor.clean(html, stripAuthorNotes: true);
      expect(stripped, contains('Story'));
      expect(stripped, isNot(contains('Author: hi')));
      expect(stripped, isNot(contains('Thanks for reading')));

      final kept = HtmlPreprocessor.clean(html, stripAuthorNotes: false);
      expect(kept, contains('Story'));
      expect(kept, contains('Author: hi'));
      expect(kept, contains('Thanks for reading'));
    });

    test('strips translator/editor credit blocks', () {
      const html =
          '<p>Story</p><p><strong>Translator: X Editor: Y</strong></p>';
      final out = HtmlPreprocessor.clean(html);
      expect(out, contains('Story'));
      expect(out, isNot(contains('Translator:')));
    });

    test('keeps credit blocks when stripBloat is false', () {
      const html =
          '<p>Story</p><p><strong>Translator: X Editor: Y</strong></p>';
      final out = HtmlPreprocessor.clean(html, stripBloat: false);
      expect(out, contains('Story'));
      expect(out, contains('Translator:'));
    });

    test('fixes lazy-load images and unwraps font tags', () {
      const html =
          '<p>Story</p><img data-src="https://x/y.png"><font>styled</font>';
      final out = HtmlPreprocessor.clean(html);
      expect(out, contains('src="https://x/y.png"'));
      expect(out, contains('styled'));
      expect(out, isNot(contains('<font>')));
    });

    test('keeps style tags for EPUB when keepCss is true', () {
      const html = '<style>p{color:red}</style><p>Story</p>';
      expect(HtmlPreprocessor.clean(html, keepCss: true), contains('<style>'));
      expect(HtmlPreprocessor.clean(html), isNot(contains('<style>')));
    });
  });
}
