enum ContentFormat { markdown, pdf }

class ChapterContent {
  final ContentFormat format;
  final String data;
  final int chapterId;

  /// Per-chapter request headers for body images (Cloudflare cookies from the
  /// jar, resolved at load time). Empty = plain requests (prior behavior).
  final Map<String, String> imageHeaders;

  const ChapterContent({
    required this.format,
    required this.data,
    required this.chapterId,
    this.imageHeaders = const {},
  });

  bool get isPdf => format == ContentFormat.pdf;
}
