import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../../core/network/client.dart';
import '../../../core/providers/engine.dart' hide ChapterContent;
import '../../../core/providers/database_providers.dart';
import '../../../core/providers/registry.dart';
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

    final instance = await _loadProvider(novel.providerId, ref);
    if (instance == null) {
      throw Exception('Provider not available for ${novel.providerId}');
    }

    final contentUrl = await instance.getChapterContentUrl(chapter.url);
    if (contentUrl == null) {
      throw Exception('Could not determine chapter URL');
    }

    final response = await dio.get(contentUrl);
    final html = response.data.toString();
    final result = await instance.parseChapterContent(html);

    if (result == null || result.html.isEmpty) {
      throw Exception('Empty content for chapter');
    }

    final cleanHtml = HtmlPreprocessor.clean(result.html);
    final md = Html2Md.convert(cleanHtml);

    Log.ok(_tag, 'Chapter "${chapter.name}" loaded: ${md.length} chars');

    return ChapterContent(
      format: ContentFormat.markdown,
      data: md,
      chapterId: chapter.id,
    );
  }

  Future<ProviderInstance?> _loadProvider(String providerId, Ref ref) async {
    final cached = ref.read(loadedProvidersProvider)[providerId];
    if (cached != null) return cached;

    final registry = await ref.read(registryManagerProvider.future);
    final engine = ref.read(providerEngineProvider);
    final jsSource = await registry.loadCachedProviderJs(providerId);
    if (jsSource == null) return null;

    final instance = await engine.loadProvider(jsSource);
    await instance.loadFlags();

    final current = ref.read(loadedProvidersProvider);
    ref.read(loadedProvidersProvider.notifier).state = {
      ...current,
      providerId: instance,
    };

    return instance;
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
