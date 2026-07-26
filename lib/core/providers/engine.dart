import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'registry.dart';
import '../utils/logger.dart';

const _tag = 'Engine';

String decodeHtmlEntities(String str) {
  str = str
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&nbsp;', ' ');
  str = str.replaceAllMapped(RegExp(r'&#(\d+);'), (m) =>
    String.fromCharCode(int.parse(m[1]!)));
  str = str.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) =>
    String.fromCharCode(int.parse(m[1]!, radix: 16)));
  return str;
}

/// Feature flags that a provider can declare via getProviderMetadata().
class ProviderFeatureFlags {
  final bool hasMainPage;
  final bool hasReviews;
  final bool hasRateLimit;
  final bool usesCloudFlareKiller;
  final bool hasSearch;
  final bool hasChapterApi;

  const ProviderFeatureFlags({
    this.hasMainPage = false,
    this.hasReviews = false,
    this.hasRateLimit = false,
    this.usesCloudFlareKiller = false,
    this.hasSearch = true,
    this.hasChapterApi = false,
  });

  factory ProviderFeatureFlags.fromJson(Map<String, dynamic> json) {
    return ProviderFeatureFlags(
      hasMainPage: json['hasMainPage'] as bool? ?? false,
      hasReviews: json['hasReviews'] as bool? ?? false,
      hasRateLimit: json['hasRateLimit'] as bool? ?? false,
      usesCloudFlareKiller: json['usesCloudFlareKiller'] as bool? ?? false,
      hasSearch: json['hasSearch'] as bool? ?? true,
      hasChapterApi: json['hasChapterApi'] as bool? ?? false,
    );
  }

  static const empty = ProviderFeatureFlags();
}

/// Wraps the JS engine for evaluating provider JS files.
class ProviderEngine {
  JavascriptRuntime? _runtime;

  void init() {
    Log.i(_tag, 'Initializing JS runtime...');
    _runtime = getJavascriptRuntime();
    Log.ok(_tag, 'JS runtime initialized');
  }

  void dispose() {
    Log.i(_tag, 'Disposing JS runtime');
    _runtime?.dispose();
    _runtime = null;
  }

  /// Load a provider from JS source code.
  Future<ProviderInstance> loadProvider(String jsSource) async {
    if (_runtime == null) init();

    Log.i(_tag, 'Loading provider (${jsSource.length} chars)...');

    final wrappedSource = '''
      var module = { exports: {} };
      $jsSource
      Object.keys(module.exports).filter(function(k) { return typeof module.exports[k] === 'function'; });
    ''';

    final result = _runtime!.evaluate(wrappedSource);
    if (result.isError) {
      Log.e(_tag, 'JS error: ${result.stringResult}');
      throw Exception('Provider JS error: ${result.stringResult}');
    }

    Log.ok(_tag, 'Provider loaded. Exported: ${result.stringResult}');

    // Parse exported function names
    final exported = ProviderInstance(runtime: _runtime!);
    try {
      final list = jsonDecode(result.stringResult) as List;
      exported._exportedFunctions = list.cast<String>();
    } catch (_) {}

    return exported;
  }
}

/// A loaded provider instance. Wraps calls to JS-exported functions.
class ProviderInstance {
  final JavascriptRuntime runtime;
  List<String> _exportedFunctions = [];
  ProviderFeatureFlags _flags = ProviderFeatureFlags.empty;

  ProviderInstance({required this.runtime});

  /// List of functions exported by this provider.
  List<String> get exportedFunctions => _exportedFunctions;

  /// Feature flags declared by this provider.
  ProviderFeatureFlags get flags => _flags;

  /// Read and cache feature flags from the provider's getProviderMetadata().
  Future<void> loadFlags() async {
    if (!_exportedFunctions.contains('getProviderMetadata')) return;
    try {
      final result = await call('getProviderMetadata', []);
      if (result != null && result is Map<String, dynamic>) {
        _flags = ProviderFeatureFlags.fromJson(result);
        Log.i(_tag, 'Flags: ${result.toString()}');
      }
    } catch (e) {
      Log.d(_tag, 'getProviderMetadata() failed: $e');
    }
  }

  /// Validate that the provider exports required functions.
  /// Returns a list of missing required functions (empty = valid).
  List<String> validate() {
    const required = ['getSearchUrl', 'parseSearchResults', 'getNovelInfoUrl', 'parseNovelInfo', 'getChapterContentUrl', 'parseChapterContent'];
    return required.where((fn) => !_exportedFunctions.contains(fn)).toList();
  }

  /// Check if a specific function is exported.
  bool hasFunction(String name) => _exportedFunctions.contains(name);

  /// Call a provider function by name and return the result.
  Future<dynamic> call(String name, List<dynamic> args) async {
    final argsJson = jsonEncode(args);
    final expr = 'JSON.stringify(module.exports.$name.apply(null, $argsJson))';
    final result = runtime.evaluate(expr);

    if (result.isError) {
      Log.e(_tag, 'Function "$name" error: ${result.stringResult}');
      throw Exception('Provider function "$name" error: ${result.stringResult}');
    }

    final str = result.stringResult;
    if (str.isEmpty || str == 'undefined' || str == 'null') return null;

    try {
      return jsonDecode(str);
    } catch (_) {
      return str;
    }
  }

  /// Full search — calls the provider's search function directly if available.
  Future<SearchResults?> search(String query, int page) async {
    try {
      final result = await call('search', [query, page]);
      if (result != null && result is Map<String, dynamic>) {
        return SearchResults.fromJson(result);
      }
    } catch (e) {
      Log.d(_tag, 'search() not available: $e');
    }
    return null;
  }

  Future<String?> getSearchUrl(String query, int page) async {
    final result = await call('getSearchUrl', [query, page]);
    return result?.toString();
  }

  Future<SearchResults?> parseSearchResults(String html) async {
    final result = await call('parseSearchResults', [html]);
    if (result == null) return null;
    try {
      if (result is Map<String, dynamic>) {
        return SearchResults.fromJson(result);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getNovelInfoUrl(String novelUrl) async {
    final result = await call('getNovelInfoUrl', [novelUrl]);
    return result?.toString();
  }

  Future<NovelInfo?> parseNovelInfo(String html) async {
    final result = await call('parseNovelInfo', [html]);
    if (result == null) return null;
    try {
      if (result is Map<String, dynamic>) {
        return NovelInfo.fromJson(result);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getChapterContentUrl(String chapterUrl) async {
    final result = await call('getChapterContentUrl', [chapterUrl]);
    return result?.toString();
  }

  Future<ChapterContent?> parseChapterContent(String html) async {
    final result = await call('parseChapterContent', [html]);
    if (result == null) return null;
    try {
      if (result is Map<String, dynamic>) {
        return ChapterContent.fromJson(result);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getImageUrl(String imgUrl) async {
    final result = await call('getImageUrl', [imgUrl]);
    return result?.toString();
  }

  // ─── Main Page / Category / Tag Browsing ─────────────────

  /// Load the main/explore page for this provider.
  /// Returns a list of novel items featured on the main page.
  Future<SearchResults?> loadMainPage({int page = 1, String? category, String? orderBy, String? tag}) async {
    try {
      final result = await call('loadMainPage', [page, category, orderBy, tag]);
      if (result != null && result is Map<String, dynamic>) {
        return SearchResults.fromJson(result);
      }
    } catch (e) {
      Log.d(_tag, 'loadMainPage() not available: $e');
    }
    return null;
  }

  /// Get available categories for browsing.
  Future<List<String>?> getCategories() async {
    try {
      final result = await call('getCategories', []);
      if (result != null && result is List) {
        return result.cast<String>();
      }
    } catch (e) {
      Log.d(_tag, 'getCategories() not available: $e');
    }
    return null;
  }

  /// Get available sort order options.
  Future<List<Map<String, String>>?> getOrderBys() async {
    try {
      final result = await call('getOrderBys', []);
      if (result != null && result is List) {
        return result.cast<Map<String, String>>();
      }
    } catch (e) {
      Log.d(_tag, 'getOrderBys() not available: $e');
    }
    return null;
  }

  /// Get available tags for filtering.
  Future<List<String>?> getTags() async {
    try {
      final result = await call('getTags', []);
      if (result != null && result is List) {
        return result.cast<String>();
      }
    } catch (e) {
      Log.d(_tag, 'getTags() not available: $e');
    }
    return null;
  }
}

// ─── Result Models ────────────────────────────────────────

class SearchResults {
  final List<SearchResultItem> results;
  final bool hasNextPage;

  SearchResults({required this.results, required this.hasNextPage});

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    final resultsList = (json['results'] as List?)
            ?.map((e) => SearchResultItem.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return SearchResults(
      results: resultsList,
      hasNextPage: json['hasNextPage'] as bool? ?? false,
    );
  }
}

class SearchResultItem {
  final String title;
  final String url;
  final String? cover;
  final String? author;
  final String? summary;
  final int? rating;
  final String? latestChapter;
  final String? providerId;
  final Map<String, String>? coverHeaders;

  SearchResultItem({
    required this.title,
    required this.url,
    this.cover,
    this.author,
    this.summary,
    this.rating,
    this.latestChapter,
    this.providerId,
    this.coverHeaders,
  });

  factory SearchResultItem.fromJson(Map<String, dynamic> json) {
    return SearchResultItem(
      title: decodeHtmlEntities(json['title'] as String? ?? ''),
      url: json['url'] as String? ?? '',
      cover: json['cover'] as String?,
      author: json['author'] != null ? decodeHtmlEntities(json['author'] as String) : null,
      summary: json['summary'] != null ? decodeHtmlEntities(json['summary'] as String) : null,
      rating: json['rating'] as int?,
      latestChapter: json['latestChapter'] as String?,
      coverHeaders: (json['coverHeaders'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString())),
    );
  }
}

class NovelInfo {
  final String title;
  final String? author;
  final String? cover;
  final String? status;
  final List<String> genres;
  final String description;
  final List<NovelChapter> chapters;
  final int? rating;
  final int? peopleVoted;
  final int? views;
  final Map<String, String>? coverHeaders;
  final List<SearchResultItem>? related;

  NovelInfo({
    required this.title,
    this.author,
    this.cover,
    this.status,
    this.genres = const [],
    required this.description,
    required this.chapters,
    this.rating,
    this.peopleVoted,
    this.views,
    this.coverHeaders,
    this.related,
  });

  factory NovelInfo.fromJson(Map<String, dynamic> json) {
    return NovelInfo(
      title: decodeHtmlEntities(json['title'] as String? ?? ''),
      author: json['author'] != null ? decodeHtmlEntities(json['author'] as String) : null,
      cover: json['cover'] as String?,
      status: json['status'] as String?,
      genres: (json['genres'] as List?)?.map((e) => decodeHtmlEntities(e as String)).toList() ?? [],
      description: decodeHtmlEntities(json['description'] as String? ?? ''),
      chapters: (json['chapters'] as List?)
              ?.map((e) => NovelChapter.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      rating: json['rating'] as int?,
      peopleVoted: json['peopleVoted'] as int?,
      views: json['views'] as int?,
      coverHeaders: (json['coverHeaders'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString())),
      related: (json['related'] as List?)
          ?.map((e) => SearchResultItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class NovelChapter {
  final String name;
  final String url;
  final String? date;
  final int? views;

  NovelChapter({required this.name, required this.url, this.date, this.views});

  factory NovelChapter.fromJson(Map<String, dynamic> json) {
    return NovelChapter(
      name: decodeHtmlEntities(json['name'] as String? ?? ''),
      url: json['url'] as String? ?? '',
      date: json['date'] as String?,
      views: json['views'] as int?,
    );
  }
}

class ChapterContent {
  final String html;
  final List<ImageRef> images;

  ChapterContent({required this.html, required this.images});

  factory ChapterContent.fromJson(Map<String, dynamic> json) {
    return ChapterContent(
      html: json['html'] as String? ?? '',
      images: (json['images'] as List?)
              ?.map((e) => ImageRef.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ImageRef {
  final String url;
  final String? alt;

  ImageRef({required this.url, this.alt});

  factory ImageRef.fromJson(Map<String, dynamic> json) {
    return ImageRef(
      url: json['url'] as String? ?? '',
      alt: json['alt'] as String?,
    );
  }
}

// ─── Riverpod Providers ───────────────────────────────────

final providerEngineProvider = Provider<ProviderEngine>((ref) {
  final engine = ProviderEngine();
  ref.onDispose(() => engine.dispose());
  return engine;
});

/// Manages loaded provider instances keyed by provider ID.
final loadedProvidersProvider =
    StateProvider<Map<String, ProviderInstance>>((ref) => {});

/// Load a provider's JS from disk cache, evaluate it, and cache the instance.
/// Returns cached instance if already loaded.
Future<ProviderInstance?> loadProviderById(
  String providerId,
  WidgetRef ref,
) async {
  // Check cache first
  final cached = ref.read(loadedProvidersProvider)[providerId];
  if (cached != null) return cached;

  final registry = await ref.read(registryManagerProvider.future);
  final engine = ref.read(providerEngineProvider);

  final jsSource = await registry.loadCachedProviderJs(providerId);
  if (jsSource == null) {
    Log.w(_tag, 'No cached JS for provider: $providerId');
    return null;
  }

  final instance = await engine.loadProvider(jsSource);

  // Load feature flags
  await instance.loadFlags();

  final current = ref.read(loadedProvidersProvider);
  ref.read(loadedProvidersProvider.notifier).state = {
    ...current,
    providerId: instance,
  };

  return instance;
}
