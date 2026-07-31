import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/utils/logger.dart';
import '../content_model.dart';
import 'content_loader.dart';

const _tag = 'DownloadedLoader';

class DownloadedLoader extends ContentLoader {
  @override
  Future<ChapterContent> load(Chapter chapter, Ref ref) async {
    final path = chapter.downloadedPath;
    if (path == null) {
      throw Exception('No download path for chapter ${chapter.id}');
    }

    Log.i(_tag, 'Loading downloaded chapter from: $path');

    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Downloaded file not found: $path');
    }

    final content = await file.readAsString();

    Log.ok(_tag, 'Downloaded chapter loaded: ${content.length} chars');

    return ChapterContent(
      format: ContentFormat.markdown,
      data: content,
      chapterId: chapter.id,
    );
  }
}
