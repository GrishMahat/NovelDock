import 'package:dio/dio.dart';

import '../../providers/engine.dart';
import '../markdown/html2md.dart';
import '../../utils/logger.dart';

const _tag = 'ChapterIntake';

/// One pipeline for turning provider HTML into the markdown a chapter
/// renders as: parse → clean → convert. The reader (`remote_loader`) and
/// the downloader must both go through here. Otherwise downloaded
/// chapters render differently from online ones.
class ChapterIntake {
  final ProviderInstance instance;
  final Dio dio;

  ChapterIntake(this.instance, this.dio);

  /// Resolve, fetch, and convert a chapter page to markdown.
  /// Returns null when the chapter URL cannot be resolved or the page
  /// carries no content.
  Future<String?> fetchMarkdown(String chapterUrl) async {
    final contentUrl = await instance.getChapterContentUrl(chapterUrl);
    if (contentUrl == null) {
      Log.w(_tag, 'Could not determine chapter URL for $chapterUrl');
      return null;
    }
    final response = await dio.get(contentUrl);
    return htmlToMarkdown(response.data.toString());
  }

  /// Parse provider HTML and convert it to markdown.
  /// Returns null when the provider reports no content.
  Future<String?> htmlToMarkdown(String html) async {
    final result = await instance.parseChapterContent(html);
    if (result == null || result.html.isEmpty) {
      Log.w(_tag, 'Provider returned empty content');
      return null;
    }
    return Html2Md.convert(HtmlPreprocessor.clean(result.html));
  }
}

class HtmlPreprocessor {
  static String clean(String html, {bool keepCss = false}) {
    var result = html
        .replaceAll(RegExp(r'<script\b[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<style\b[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<nav\b[^>]*>.*?</nav>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<header\b[^>]*>.*?</header>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<footer\b[^>]*>.*?</footer>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<aside\b[^>]*>.*?</aside>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<form\b[^>]*>.*?</form>', caseSensitive: false, dotAll: true), '')
        .replaceAll(RegExp(r'<noscript\b[^>]*>.*?</noscript>', caseSensitive: false, dotAll: true), '');
    if (!keepCss) {
      result = result.replaceAll(RegExp(r'\sclass="[^"]*"'), '');
      result = result.replaceAll(RegExp(r"\sclass='[^']*'"), '');
      result = result.replaceAll(RegExp(r'\sid="[^"]*"'), '');
      result = result.replaceAll(RegExp(r"\sid='[^']*'"), '');
    }
    return result;
  }
}
