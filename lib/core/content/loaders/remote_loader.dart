import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_prefs.dart';
import '../../../core/database/database.dart';
import '../../../core/network/client.dart';
import '../../../core/network/image_headers.dart';
import '../../../core/providers/engine.dart' hide ChapterContent;
import '../../../core/providers/database_providers.dart';
import '../../../core/utils/html_preprocessor.dart';
import '../../../core/utils/logger.dart';
import '../content_model.dart';
import '../markdown/html2md.dart';
import 'content_loader.dart';

const _tag = 'RemoteLoader';

class RemoteLoader extends ContentLoader {
  @override
  Future<ChapterContent> load(Chapter chapter, Ref ref) async {
    final dio = await ref.read(dioProvider.future);
    final novelDao = ref.read(novelDaoProvider);
    final novel = await novelDao.getNovelById(chapter.novelId);

    if (novel == null) {
      throw Exception('Novel not found for id ${chapter.novelId}');
    }

    final instance = await ref.read(
      providerInstanceProvider(novel.providerId).future,
    );
    if (instance == null) {
      throw Exception('Provider not available for ${novel.providerId}');
    }

    final contentUrl = await instance.getChapterContentUrl(chapter.url);
    if (contentUrl == null) {
      throw Exception('Could not determine chapter URL');
    }

    // Plain text: dio's default ResponseType.json auto-parses JSON responses
    // (e.g. novelarrow's api-web chapter API) into a Dart Map whose
    // toString() is not valid JSON/HTML for the provider parsers.
    final response = await dio.get(
      contentUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final html = response.data.toString();
    final result = await instance.parseChapterContent(html);

    if (result == null || result.html.isEmpty) {
      throw Exception('Empty content for chapter');
    }

    final prefs = ref.read(appPrefsProvider);
    final cleanHtml = HtmlPreprocessor.clean(
      result.html,
      stripAuthorNotes: !(prefs.getBool('reader_show_author_notes') ?? true),
      stripBloat: prefs.getBool('reader_remove_bloat') ?? true,
    );
    final md = Html2Md.convert(cleanHtml);

    Log.ok(_tag, 'Chapter "${chapter.name}" loaded: ${md.length} chars');

    return ChapterContent(
      format: ContentFormat.markdown,
      data: md,
      chapterId: chapter.id,
      imageHeaders: await imageHeadersForUrl(contentUrl, ref),
    );
  }
}
