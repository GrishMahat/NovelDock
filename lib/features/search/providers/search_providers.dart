import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/providers/engine.dart';
import '../../../core/providers/registry.dart';
import '../../../core/network/client.dart';
import '../../../core/utils/logger.dart';
import '../../settings/providers/provider_management_providers.dart';

const _tag = 'Search';

/// Search results state
class SearchState {
  final List<SearchResultItem> results;
  final bool isLoading;
  final String? error;
  final bool hasNextPage;

  const SearchState({
    this.results = const [],
    this.isLoading = false,
    this.error,
    this.hasNextPage = false,
  });

  SearchState copyWith({
    List<SearchResultItem>? results,
    bool? isLoading,
    String? error,
    bool? hasNextPage,
  }) {
    return SearchState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      hasNextPage: hasNextPage ?? this.hasNextPage,
    );
  }
}

/// Search notifier that queries providers
class SearchNotifier extends StateNotifier<SearchState> {
  final Ref ref;

  SearchNotifier(this.ref) : super(const SearchState());

  Future<void> search(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return;

    Log.i(_tag, 'Searching for: "$query" (page $page)');
    state = state.copyWith(isLoading: true, error: null);

    try {
      final enabledProviders = ref.read(enabledProvidersProvider);
      final dio = await ref.read(dioProvider.future);

      Log.i(_tag, 'Searching ${enabledProviders.length} enabled providers: $enabledProviders');

      final allResults = <SearchResultItem>[];

      for (final providerId in enabledProviders) {
        try {
          Log.i(_tag, 'Searching provider: $providerId');

          // Check cache first
          final cached = ref.read(loadedProvidersProvider)[providerId];
          if (cached == null) {
            Log.e(_tag, 'No cached provider for $providerId, skipping');
            continue;
          }
          final instance = cached;

          List<SearchResultItem> tagResults(List<SearchResultItem> items) {
            return items.map((e) => SearchResultItem(
              title: e.title,
              url: e.url,
              cover: e.cover,
              author: e.author,
              summary: e.summary,
              rating: e.rating,
              latestChapter: e.latestChapter,
              providerId: providerId,
              coverHeaders: e.coverHeaders,
            )).toList();
          }

          // 1. Try POST-based search first (provider defines getSearchConfig)
          final searchConfig = await instance.call('getSearchConfig', []);
          if (searchConfig != null && searchConfig is Map<String, dynamic>) {
            Log.i(_tag, 'Provider uses POST search');
            final results = await _postSearch(instance, dio, searchConfig, query, page);
            if (results != null) {
              Log.ok(_tag, 'Got ${results.results.length} results from $providerId (POST)');
              allResults.addAll(tagResults(results.results));
              continue;
            }
          }

          // 2. Try direct search function
          final directResults = await instance.search(query, page);
          if (directResults != null && directResults.results.isNotEmpty) {
            Log.ok(_tag, 'Got ${directResults.results.length} results from $providerId (direct)');
            allResults.addAll(tagResults(directResults.results));
            continue;
          }

          // 3. Fall back to URL-based GET search
          final searchUrl = await instance.getSearchUrl(query, page);
          if (searchUrl == null) {
            Log.e(_tag, 'No search URL for $providerId, skipping');
            continue;
          }

          Log.i(_tag, 'Fetching: $searchUrl');
          final response = await dio.get(searchUrl);
          final html = response.data.toString();
          Log.i(_tag, 'Got ${html.length} chars of HTML from $providerId');

          final results = await instance.parseSearchResults(html);
          if (results != null) {
            Log.ok(_tag, 'Parsed ${results.results.length} results from $providerId');
            allResults.addAll(tagResults(results.results));
          } else {
            Log.w(_tag, 'parseSearchResults returned null for $providerId');
          }
        } catch (e) {
          Log.e(_tag, 'Error with $providerId', e);
        }
      }

      Log.ok(_tag, 'Total results: ${allResults.length}');
      state = state.copyWith(
        results: allResults,
        isLoading: false,
        hasNextPage: allResults.length >= 20,
      );
    } catch (e) {
      Log.e(_tag, 'Search failed', e);
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Handle POST-based search — headers come from the provider's getSearchConfig()
  Future<SearchResults?> _postSearch(
    ProviderInstance instance,
    dynamic dio,
    Map<String, dynamic> config,
    String query,
    int page,
  ) async {
    try {
      final url = config['url'] as String?;
      final fields = config['fields'] as Map<String, dynamic>?;
      final headers = config['headers'] as Map<String, dynamic>?;
      final resultPattern = config['resultUrlPattern'] as String?;
      final searchIdRegex = config['searchIdRegex'] as String?;

      if (url == null) return null;

      // Build form data from provider config
      final formData = <String, String>{
        if (fields != null) ...fields.map((k, v) => MapEntry(k, v.toString())),
        'keyboard': query,
      };

      // Build headers from provider config
      final requestHeaders = <String, String>{
        if (headers != null) ...headers.map((k, v) => MapEntry(k, v.toString())),
      };

      // Build form data as URL-encoded string (not multipart)
      final formBody = formData.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      Log.i(_tag, 'POST $url');
      Log.d(_tag, 'Body: $formBody');
      Log.d(_tag, 'Headers: $requestHeaders');

      // POST with application/x-www-form-urlencoded
      final response = await dio.post(
        url,
        data: formBody,
        options: Options(
          headers: {
            ...requestHeaders,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      Log.i(_tag, 'POST status: ${response.statusCode}');

      // Extract search ID from Location header (302 redirect)
      String? searchId;
      if (response.statusCode == 301 || response.statusCode == 302) {
        final location = response.headers.value('location') ?? '';
        Log.i(_tag, 'Redirect Location: $location');
        if (searchIdRegex != null) {
          final match = RegExp(searchIdRegex).firstMatch(location);
          searchId = match?.group(1);
        }
      }

      if (searchId == null) {
        Log.e(_tag, 'No search ID found. Status: ${response.statusCode}');
        return null;
      }

      Log.i(_tag, 'Got search ID: $searchId');

      // Step 2: Fetch results page using proper URL pattern
      if (resultPattern == null) return null;
      final resultUrl = resultPattern
          .replaceAll('{page}', page.toString())
          .replaceAll('{searchid}', searchId);

      Log.i(_tag, 'Fetching results: $resultUrl');
      final resultResponse = await dio.get(resultUrl);
      final html = resultResponse.data.toString();
      Log.i(_tag, 'Got ${html.length} chars of HTML');

      return await instance.parseSearchResults(html);
    } catch (e) {
      Log.e(_tag, 'POST search failed', e);
      return null;
    }
  }

  void clear() {
    state = const SearchState();
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref);
});
