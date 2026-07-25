import 'package:html/parser.dart' as html_parser;

/// Preprocesses chapter HTML before rendering.
/// Mirrors the original Kotlin preParseHtml() — strips ads, scripts,
/// unwanted elements, and cleans up HTML for display.
class HtmlPreprocessor {
  /// Clean HTML content for rendering.
  /// Returns cleaned HTML string.
  /// If [keepCss] is true, preserves <style> and <link> tags (for EPUB content).
  static String clean(String rawHtml, {bool stripAuthorNotes = true, bool keepCss = false}) {
    final document = html_parser.parse(rawHtml);

    // 1. Remove <script> tags
    document.querySelectorAll('script').forEach((e) => e.remove());

    // 2. Remove <style> tags (unless keepCss for EPUB)
    if (!keepCss) {
      document.querySelectorAll('style').forEach((e) => e.remove());
    }

    // 3. Remove <iframe> tags (ads, trackers)
    document.querySelectorAll('iframe').forEach((e) => e.remove());

    // 4. Remove <noscript> tags
    document.querySelectorAll('noscript').forEach((e) => e.remove());

    // 5. Remove <link> tags (external stylesheets) — keep for EPUB
    if (!keepCss) {
      document.querySelectorAll('link').forEach((e) => e.remove());
    }

    // 6. Remove <meta> tags
    document.querySelectorAll('meta').forEach((e) => e.remove());

    // 7. Remove ad-related elements
    document.querySelectorAll('[class*="ad"], [class*="Ad"], [id*="ad"], [id*="Ad"]').forEach((e) => e.remove());
    document.querySelectorAll('[class*="banner"], [class*="Banner"]').forEach((e) => e.remove());
    document.querySelectorAll('[class*="popup"], [class*="Popup"]').forEach((e) => e.remove());
    document.querySelectorAll('[class*="modal"], [class*="Modal"]').forEach((e) => e.remove());
    document.querySelectorAll('[class*="overlay"], [class*="Overlay"]').forEach((e) => e.remove());

    // 8. Remove tracking pixels (1x1 images)
    document.querySelectorAll('img[width="1"], img[height="1"]').forEach((e) => e.remove());
    document.querySelectorAll('img[style*="display:none"], img[style*="visibility:hidden"]').forEach((e) => e.remove());

    // 9. Remove empty divs and spans (common in ad containers)
    document.querySelectorAll('div, span').forEach((e) {
      if (e.text.trim().isEmpty && e.children.isEmpty) {
        e.remove();
      }
    });

    // 10. Remove author notes container (if enabled)
    if (stripAuthorNotes) {
      document.querySelectorAll('.qnauthornotecontainer').forEach((e) => e.remove());
      document.querySelectorAll('[class*="author-note"], [class*="authorNote"]').forEach((e) => e.remove());
    }

    // 11. Remove translator/editor credit blocks
    // Original regex: <p>.*<strong>Translator:.*Editor:.*> and <.*?Translator:.*?Editor:.*?>
    document.querySelectorAll('p, div, span').forEach((e) {
      final text = e.text;
      if (text.contains('Translator:') && text.contains('Editor:')) {
        e.remove();
      }
    });

    // 12. Fix relative image URLs (make them absolute)
    document.querySelectorAll('img').forEach((img) {
      final src = img.attributes['src'];
      if (src != null && !src.startsWith('http') && !src.startsWith('data:')) {
        // Can't resolve relative URLs without base URL here
        // The caller should handle this if needed
      }

      // Remove lazy-load attributes that might cause issues
      img.attributes.remove('loading');
      img.attributes.remove('decoding');

      // Fix common broken attributes
      final dataSrc = img.attributes['data-src'];
      if (dataSrc != null && dataSrc.isNotEmpty) {
        img.attributes['src'] = dataSrc;
        img.attributes.remove('data-src');
      }
    });

    // 13. Clean up tables — add basic styling
    document.querySelectorAll('table').forEach((table) {
      table.attributes['style'] = 'border-collapse: collapse; width: 100%;';
    });

    document.querySelectorAll('td, th').forEach((cell) {
      final existingStyle = cell.attributes['style'] ?? '';
      cell.attributes['style'] = '$existingStyle padding: 4px 8px; border: 1px solid #444;'.trim();
    });

    // 14. Convert ... to unicode ellipsis
    document.body?.innerHtml = document.body?.innerHtml
            .replaceAll('...', '\u2026')
            .replaceAll('....', '\u2026') ??
        '';

    // 15. Remove <center> tags (unwrap content)
    document.querySelectorAll('center').forEach((center) {
      for (final child in center.children.toList()) {
        center.parent?.insertBefore(child, center);
      }
      center.remove();
    });

    // 16. Remove <font> tags (unwrap content)
    document.querySelectorAll('font').forEach((font) {
      for (final child in font.children.toList()) {
        font.parent?.insertBefore(child, font);
      }
      font.remove();
    });

    return document.body?.innerHtml ?? rawHtml;
  }
}
