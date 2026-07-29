import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/content/markdown/html2md.dart';

void main() {
  group('Html2Md', () {
    test('converts paragraph', () {
      final md = Html2Md.convert('<p>Hello world</p>');
      expect(md, 'Hello world');
    });

    test('converts heading', () {
      final md = Html2Md.convert('<h1>Title</h1>');
      expect(md, '# Title');
    });

    test('converts heading level 2', () {
      final md = Html2Md.convert('<h2>Subtitle</h2>');
      expect(md, '## Subtitle');
    });

    test('converts bold', () {
      final md = Html2Md.convert('<p><strong>bold</strong> text</p>');
      expect(md, '**bold** text');
    });

    test('converts italic', () {
      final md = Html2Md.convert('<p><em>italic</em> text</p>');
      expect(md, '*italic* text');
    });

    test('converts link', () {
      final md = Html2Md.convert('<p>Click <a href="https://example.com">here</a></p>');
      expect(md, 'Click [here](https://example.com)');
    });

    test('converts image', () {
      final md = Html2Md.convert('<p><img src="pic.jpg" alt="Alt text"/></p>');
      expect(md, '![Alt text](pic.jpg)');
    });

    test('converts inline code', () {
      final md = Html2Md.convert('<p>Use <code>var</code></p>');
      expect(md, 'Use `var`');
    });

    test('converts code block', () {
      final md = Html2Md.convert('<pre><code class="language-dart">void main() {}</code></pre>');
      expect(md, '```dart\nvoid main() {}\n```');
    });

    test('converts unordered list', () {
      final md = Html2Md.convert('<ul><li>One</li><li>Two</li></ul>');
      expect(md, '- One\n- Two');
    });

    test('converts blockquote', () {
      final md = Html2Md.convert('<blockquote><p>Quote text</p></blockquote>');
      expect(md, '> Quote text');
    });

    test('converts horizontal rule', () {
      final md = Html2Md.convert('<hr/>');
      expect(md, '---');
    });

    test('strips script tags', () {
      final md = Html2Md.convert('<p>Hello</p><script>alert("xss")</script>');
      expect(md, 'Hello');
    });

    test('strips style tags', () {
      final md = Html2Md.convert('<p>Hello</p><style>body{}</style>');
      expect(md, 'Hello');
    });

    test('converts nested inline formatting', () {
      final md = Html2Md.convert('<p><strong>bold <em>and italic</em></strong></p>');
      expect(md, '**bold *and italic***');
    });

    test('empty input returns empty string', () {
      expect(Html2Md.convert(''), '');
      expect(Html2Md.convert('   '), '');
    });

    test('converts multiple paragraphs', () {
      final md = Html2Md.convert('<p>First</p><p>Second</p>');
      expect(md, 'First\n\nSecond');
    });

    test('converts ordered list', () {
      final md = Html2Md.convert('<ol><li>One</li><li>Two</li></ol>');
      expect(md, '1. One\n2. Two');
    });

    test('converts nested list', () {
      final md = Html2Md.convert('<ul><li>A</li><li>B<ul><li>B1</li></ul></li></ul>');
      expect(md, contains('- A'));
      expect(md, contains('- B'));
      expect(md, contains('- B1'));
    });

    test('converts <b> as bold', () {
      final md = Html2Md.convert('<p><b>bold</b></p>');
      expect(md, '**bold**');
    });

    test('converts <i> as italic', () {
      final md = Html2Md.convert('<p><i>italic</i></p>');
      expect(md, '*italic*');
    });

    test('converts <em> inside <strong>', () {
      final md = Html2Md.convert('<p><strong>bold <em>and italic</em></strong></p>');
      expect(md, '**bold *and italic***');
    });

    test('converts section and article tags', () {
      final md = Html2Md.convert('<section><p>Hello</p></section><article><p>World</p></article>');
      expect(md, 'Hello\n\nWorld');
    });

    test('converts table with header and data', () {
      final md = Html2Md.convert('<table><tr><th>Name</th><th>Age</th></tr><tr><td>Alice</td><td>30</td></tr></table>');
      expect(md, contains('Name | Age'));
      expect(md, contains('Alice | 30'));
    });

    test('strips nav, header, footer, aside, iframe', () {
      final md = Html2Md.convert('<p>Content</p><nav>Nav</nav><header>Header</header><footer>Footer</footer><aside>Aside</aside><iframe src="x"></iframe>');
      expect(md.trim(), 'Content');
    });

    test('converts line break', () {
      final md = Html2Md.convert('<p>Line1<br/>Line2</p>');
      expect(md, 'Line1  \nLine2');
    });

    test('converts div containing paragraphs', () {
      final md = Html2Md.convert('<div><p>One</p><p>Two</p></div>');
      expect(md, 'One\n\nTwo');
    });

    test('handles HTML with no body content', () {
      final md = Html2Md.convert('<html><head></head></html>');
      expect(md, '');
    });
  });
}
