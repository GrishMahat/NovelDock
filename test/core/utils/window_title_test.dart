import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/utils/window_title.dart';

void main() {
  group('titleFor', () {
    test('main tabs', () {
      expect(titleFor('/library'), 'NovelDock — Library');
      expect(titleFor('/browse'), 'NovelDock — Browse');
      expect(titleFor('/history'), 'NovelDock — History');
      expect(titleFor('/downloads'), 'NovelDock — Downloads');
      expect(titleFor('/settings'), 'NovelDock — Settings');
    });

    test('sub-pages', () {
      expect(titleFor('/search/results?q=x'), 'NovelDock — Search');
      expect(titleFor('/provider/wuxiabox'), 'NovelDock — Source');
      expect(titleFor('/novel/12'), 'NovelDock — Details');
      expect(titleFor('/reader/12/34'), 'NovelDock — Reader');
      expect(titleFor('/settings/about'), 'NovelDock — Settings');
      expect(titleFor('/import?file=/x.epub'), 'NovelDock — Import');
    });

    test('unknown locations fall back to the app name', () {
      expect(titleFor('/nope'), 'NovelDock');
      expect(titleFor(''), 'NovelDock');
    });
  });
}
