enum ContentFormat { markdown, pdf }

class ChapterContent {
  final ContentFormat format;
  final String data;
  final int chapterId;

  const ChapterContent({
    required this.format,
    required this.data,
    required this.chapterId,
  });

  bool get isPdf => format == ContentFormat.pdf;
}
