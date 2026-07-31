import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/utils/logger.dart';
import '../content_model.dart';
import 'content_loader.dart';

const _tag = 'PdfLoader';

class PdfLoader extends ContentLoader {
  @override
  Future<ChapterContent> load(Chapter chapter, Ref ref) async {
    final url = chapter.url;
    final filePath = url.replaceFirst('pdf://', '').split('#').first;

    Log.i(_tag, 'Loading PDF from: $filePath');

    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('PDF file not found: $filePath');
    }

    return ChapterContent(
      format: ContentFormat.pdf,
      data: filePath,
      chapterId: chapter.id,
    );
  }
}
