import 'dart:io';

import 'package:epubx_kuebiko/epubx_kuebiko.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/utils/logger.dart';
import '../content_model.dart';
import '../markdown/html2md.dart';
import 'content_loader.dart';
import 'remote_loader.dart';

const _tag = 'EpubLoader';

class EpubLoader extends ContentLoader {
  @override
  Future<ChapterContent> load(Chapter chapter, Ref ref) async {
    final url = chapter.url;
    final filePath = url.replaceFirst('epub://', '').split('#').first;

    Log.i(_tag, 'Loading EPUB chapter from: $filePath');

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('EPUB file not found: $filePath');
    }

    final bytes = await file.readAsBytes();
    final book = await EpubReader.readBook(bytes);

    if (book.Chapters == null || book.Chapters!.isEmpty) {
      throw Exception('No chapters in EPUB');
    }

    final chIndex = (chapter.index.toInt()).clamp(0, book.Chapters!.length - 1);
    final ch = book.Chapters![chIndex];
    final html = ch.HtmlContent ?? '';
    final cleanHtml = HtmlPreprocessor.clean(html, keepCss: true);
    final md = Html2Md.convert(cleanHtml);

    Log.ok(_tag, 'EPUB chapter ${chIndex + 1} loaded: ${md.length} chars');

    return ChapterContent(
      format: ContentFormat.markdown,
      data: md,
      chapterId: chapter.id,
    );
  }
}
