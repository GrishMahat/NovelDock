import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/providers/engine.dart';
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

      // Rank results by fuzzy relevance
      final ranked = _rankResults(allResults, query);
      Log.ok(_tag, 'Total results: ${ranked.length}');
      state = state.copyWith(
        results: ranked,
        isLoading: false,
        hasNextPage: ranked.length >= 20,
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

  /// Rank search results by fuzzy relevance to the query.
  /// Uses token-based scoring: title match > author match > summary match,
  /// weighted by token proximity and substring containment.
  List<SearchResultItem> _rankResults(List<SearchResultItem> results, String query) {
    if (results.isEmpty) return results;

    final queryTokens = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (queryTokens.isEmpty) return results;

    // Score each result
    final scored = results.map((item) {
      final title = item.title.toLowerCase();
      final author = item.author?.toLowerCase() ?? '';
      final summary = item.summary?.toLowerCase() ?? '';

      double score = 0;

      for (final token in queryTokens) {
        // Exact title match: highest score
        if (title == token) {
          score += 100;
        } else if (title.contains(token)) {
          score += 50;
        } else {
          // Fuzzy title match via Levenshtein
          final dist = _levenshteinDistance(token, title);
          if (dist <= 2) {
            score += 30 * (1 - dist / title.length);
          }
        }

        // Token-in-summary bonus
        if (summary.contains(token)) {
          score += 10;
        }

        // Token-in-author bonus
        if (author.contains(token)) {
          score += 5;
        }

        // Full query as substring of title
        if (title.contains(query.toLowerCase())) {
          score += 20;
        }
      }

      // Normalize by title length (shorter = denser match)
      if (title.isNotEmpty) {
        score = score / (title.length / 10);
      }

      return (item: item, score: score);
    }).toList();

    // Sort descending by score
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((s) => s.item).toList();
  }

  /// Simple Levenshtein distance between two strings.
  int _levenshteinDistance(String a, String b) {
    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (var i = 0; i <= m; i++) dp[i][0] = i;
    for (var j = 0; j <= n; j++) dp[0][j] = j;

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }

    return dp[m][n];
  }

  void clear() {
    state = const SearchState();
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref);
});
