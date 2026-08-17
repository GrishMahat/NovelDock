import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/providers/engine.dart';
import '../../../core/providers/filters.dart';
import '../../../core/network/client.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/utils/logger.dart';
import '../../settings/providers/provider_management_providers.dart';

const _tag = 'Search';

// ═══════════════════════════════════════════════════════════
// State
// ═══════════════════════════════════════════════════════════

/// State for a single provider's search results.
class ProviderSearchState {
  final List<SearchResultItem> results;
  final bool isLoading;
  final bool hasNextPage;
  final String? error;
  final int loadedPages;

  const ProviderSearchState({
    this.results = const [],
    this.isLoading = false,
    this.hasNextPage = false,
    this.error,
    this.loadedPages = 0,
  });

  bool get loaded => loadedPages > 0;

  ProviderSearchState copyWith({
    List<SearchResultItem>? results,
    bool? isLoading,
    bool? hasNextPage,
    String? error,
    int? loadedPages,
  }) {
    return ProviderSearchState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      error: error ?? this.error,
      loadedPages: loadedPages ?? this.loadedPages,
    );
  }
}

/// Aggregate search state across providers.
class SearchState {
  final String query;
  final Map<String, ProviderSearchState> providers;
  final List<String> providerOrder;
  final Set<String> selectedProviders;
  final Map<String, FilterValues> filters;

  const SearchState({
    this.query = '',
    this.providers = const {},
    this.providerOrder = const [],
    this.selectedProviders = const {},
    this.filters = const {},
  });

  bool get isLoading =>
      providers.values.any((p) => p.isLoading) && !hasAnyResults;

  bool get hasAnyResults => providers.values.any((p) => p.results.isNotEmpty);

  int get totalResults =>
      providers.values.fold(0, (sum, p) => sum + p.results.length);

  ProviderSearchState stateFor(String providerId) =>
      providers[providerId] ?? const ProviderSearchState();

  List<String> get providersWithResults =>
      providerOrder.where((id) => stateFor(id).loaded).toList();

  FilterValues filtersFor(String providerId) =>
      filters[providerId] ?? const FilterValues();

  bool get hasActiveFilters => filters.values.any((f) => !f.isEmpty);

  SearchState copyWith({
    String? query,
    Map<String, ProviderSearchState>? providers,
    List<String>? providerOrder,
    Set<String>? selectedProviders,
    Map<String, FilterValues>? filters,
  }) {
    return SearchState(
      query: query ?? this.query,
      providers: providers ?? this.providers,
      providerOrder: providerOrder ?? this.providerOrder,
      selectedProviders: selectedProviders ?? this.selectedProviders,
      filters: filters ?? this.filters,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Search history
// ═══════════════════════════════════════════════════════════

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
      return SearchHistoryNotifier(ref);
    });

class SearchHistoryNotifier extends StateNotifier<List<String>> {
  final Ref ref;

  static const _key = 'search_history';
  static const _maxEntries = 12;

  Future<void> _saveQueue = Future<void>.value();
  int _mutationVersion = 0;

  SearchHistoryNotifier(this.ref) : super(const []) {
    _load();
  }

  Future<void> _load() async {
    final loadVersion = _mutationVersion;

    try {
      final settingsDao = ref.read(settingsDaoProvider);
      final value = await settingsDao.getSetting(_key);

      // Do not overwrite a value modified locally while the load
      // was still in progress.
      if (loadVersion != _mutationVersion) return;

      if (value != null && value.isNotEmpty) {
        final decoded = jsonDecode(value);

        if (decoded is List) {
          state = decoded
              .whereType<String>()
              .take(_maxEntries)
              .toList(growable: false);
        }
      }
    } catch (e) {
      Log.w(_tag, 'Failed to load search history: $e');
    }
  }

  Future<void> _save() {
    final snapshot = List<String>.unmodifiable(state);

    _saveQueue = _saveQueue.then((_) async {
      try {
        final settingsDao = ref.read(settingsDaoProvider);
        await settingsDao.setSetting(_key, jsonEncode(snapshot));
      } catch (e) {
        Log.w(_tag, 'Failed to save search history: $e');
      }
    });

    return _saveQueue;
  }

  void add(String query) {
    final q = query.trim();
    if (q.isEmpty) return;

    _mutationVersion++;

    state = [q, ...state.where((e) => e != q)].take(_maxEntries).toList();

    _save();
  }

  void remove(String query) {
    _mutationVersion++;

    state = state.where((e) => e != query).toList();
    _save();
  }

  void clear() {
    _mutationVersion++;

    state = const [];
    _save();
  }
}

// ═══════════════════════════════════════════════════════════
// Provider selection
// ═══════════════════════════════════════════════════════════

/// Which providers participate in global search.
///
/// Before the user explicitly chooses providers, all enabled providers
/// participate. Once the user explicitly chooses, the exact selected set
/// is respected, including an intentionally empty set.
final searchProviderSelectionProvider =
    StateNotifierProvider<SearchProviderSelectionNotifier, Set<String>>(
      (ref) => SearchProviderSelectionNotifier(ref),
    );

class SearchProviderSelectionNotifier extends StateNotifier<Set<String>> {
  final Ref ref;

  static const _key = 'search_providers';

  bool _explicit = false;

  Future<void> _saveQueue = Future<void>.value();
  int _mutationVersion = 0;

  SearchProviderSelectionNotifier(this.ref) : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    final loadVersion = _mutationVersion;

    try {
      final settingsDao = ref.read(settingsDaoProvider);
      final value = await settingsDao.getSetting(_key);

      if (loadVersion != _mutationVersion) return;

      if (value != null && value.isNotEmpty) {
        final decoded = jsonDecode(value);

        if (decoded is List) {
          _explicit = true;
          state = decoded.whereType<String>().toSet();
        }
      }
    } catch (e) {
      Log.w(_tag, 'Failed to load search provider selection: $e');
    }
  }

  Future<void> _save() {
    final snapshot = Set<String>.unmodifiable(state);

    _saveQueue = _saveQueue.then((_) async {
      try {
        final settingsDao = ref.read(settingsDaoProvider);
        await settingsDao.setSetting(_key, jsonEncode(snapshot.toList()));
      } catch (e) {
        Log.w(_tag, 'Failed to save search provider selection: $e');
      }
    });

    return _saveQueue;
  }

  /// Effective selection:
  /// - before explicit selection: all enabled providers
  /// - after explicit selection: exactly the selected enabled providers
  ///
  /// An explicit empty selection means no providers.
  Set<String> effective(Set<String> enabled) {
    if (!_explicit) return Set.of(enabled);
    return state.where(enabled.contains).toSet();
  }

  void toggle(String providerId) {
    _explicit = true;
    _mutationVersion++;

    final next = Set<String>.from(state);

    if (!next.add(providerId)) {
      next.remove(providerId);
    }

    state = next;
    _save();
  }

  void setAll(Set<String> providerIds) {
    _explicit = true;
    _mutationVersion++;

    state = Set.of(providerIds);
    _save();
  }
}

// ═══════════════════════════════════════════════════════════
// Notifier
// ═══════════════════════════════════════════════════════════

class SearchNotifier extends StateNotifier<SearchState> {
  final Ref ref;

  SearchNotifier(this.ref) : super(const SearchState());

  /// Monotonically increasing request token per provider.
  ///
  /// Every new request invalidates the previous request for that provider.
  /// This lets a new query or filter search start immediately instead of
  /// being blocked behind stale work.
  final Map<String, int> _requestTokens = {};

  int _nextRequestToken(String providerId) {
    final token = (_requestTokens[providerId] ?? 0) + 1;
    _requestTokens[providerId] = token;
    return token;
  }

  bool _isCurrentRequest(String providerId, int token) {
    return _requestTokens[providerId] == token;
  }

  /// Start a fresh search across all selected providers (page 1).
  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    Log.i(_tag, 'Searching for: "$q"');

    ref.read(searchHistoryProvider.notifier).add(q);

    final enabled = ref.read(enabledProvidersProvider);
    final selected = ref
        .read(searchProviderSelectionProvider.notifier)
        .effective(enabled);

    state = SearchState(
      query: q,
      providerOrder: enabled.toList(),
      selectedProviders: selected,
      filters: state.filters,
    );

    if (selected.isEmpty) return;

    await Future.wait(
      selected.map((id) => _searchProvider(id, page: 1, replace: true)),
    );
  }

  /// Fetch the next page for one provider.
  Future<void> loadMore(String providerId) async {
    final ps = state.stateFor(providerId);

    if (ps.isLoading || !ps.hasNextPage) return;
    if (!state.selectedProviders.contains(providerId)) return;

    await _searchProvider(providerId, page: ps.loadedPages + 1);
  }

  /// Retry the first page for one provider.
  Future<void> retryProvider(String providerId) async {
    if (state.query.isEmpty) return;
    if (!state.selectedProviders.contains(providerId)) return;

    await _searchProvider(providerId, page: 1, replace: true);
  }

  /// Apply filters for one provider and re-run its search from page 1.
  Future<void> setFilters(String providerId, FilterValues values) async {
    final nextFilters = Map<String, FilterValues>.of(state.filters)
      ..[providerId] = values;

    state = state.copyWith(filters: nextFilters);

    if (state.query.isEmpty) return;
    if (!state.selectedProviders.contains(providerId)) return;

    await _searchProvider(providerId, page: 1, replace: true);
  }

  Future<void> clearFilters(String providerId) =>
      setFilters(providerId, const FilterValues());

  /// Re-run the search when the provider selection changes.
  Future<void> refreshSelection() async {
    if (state.query.isEmpty) return;

    final enabled = ref.read(enabledProvidersProvider);
    final selected = ref
        .read(searchProviderSelectionProvider.notifier)
        .effective(enabled);

    final previousProviders = state.providers;

    state = state.copyWith(
      selectedProviders: selected,
      providers: {
        for (final entry in previousProviders.entries)
          if (selected.contains(entry.key)) entry.key: entry.value,
      },
    );

    if (selected.isEmpty) return;

    await Future.wait(
      selected.map((id) => _searchProvider(id, page: 1, replace: true)),
    );
  }

  Future<void> _searchProvider(
    String providerId, {
    required int page,
    bool replace = false,
  }) async {
    if (!state.selectedProviders.contains(providerId)) return;

    final requestToken = _nextRequestToken(providerId);

    final expectedQuery = state.query;
    final filters = state.filtersFor(providerId);

    final prev = state.stateFor(providerId);

    final nextState = replace || page == 1
        ? const ProviderSearchState(isLoading: true)
        : prev.copyWith(isLoading: true);

    _updateProviderIfCurrentQuery(providerId, nextState, expectedQuery);

    try {
      var cached = ref.read(loadedProvidersProvider)[providerId];

      if (cached == null) {
        Log.i(_tag, 'Loading provider JS for $providerId...');
        cached = await loadProviderById(providerId, ref.container);
      }

      if (!_isCurrentRequest(providerId, requestToken)) return;
      if (state.query != expectedQuery) return;

      if (cached == null) {
        Log.w(_tag, 'Could not load provider $providerId, skipping');

        _updateProviderIfCurrentRequest(
          providerId,
          requestToken,
          ProviderSearchState(isLoading: false, error: 'Provider not loaded'),
          expectedQuery,
        );

        return;
      }

      final dio = await ref.read(dioProvider.future);

      if (!_isCurrentRequest(providerId, requestToken)) return;
      if (state.query != expectedQuery) return;

      final results = await _searchProviderOnce(
        cached,
        dio,
        expectedQuery,
        filters,
        page,
      );

      if (!_isCurrentRequest(providerId, requestToken)) return;
      if (state.query != expectedQuery) return;

      if (results == null) {
        _updateProviderIfCurrentRequest(
          providerId,
          requestToken,
          nextState.copyWith(isLoading: false, error: 'No results'),
          expectedQuery,
        );

        return;
      }

      final tagged = results.results
          .map(
            (e) => SearchResultItem(
              title: e.title,
              url: e.url,
              cover: e.cover,
              author: e.author,
              summary: e.summary,
              rating: e.rating,
              latestChapter: e.latestChapter,
              providerId: providerId,
              coverHeaders: e.coverHeaders,
            ),
          )
          .toList();

      final merged = replace || page == 1
          ? tagged
          : [...prev.results, ...tagged];

      _updateProviderIfCurrentRequest(
        providerId,
        requestToken,
        ProviderSearchState(
          results: merged,
          isLoading: false,
          hasNextPage: results.hasNextPage,
          error: null,
          loadedPages: page,
        ),
        expectedQuery,
      );

      Log.ok(
        _tag,
        'Got ${tagged.length} results from $providerId (page $page)',
      );
    } catch (e) {
      Log.e(_tag, 'Error searching $providerId', e);

      if (!_isCurrentRequest(providerId, requestToken)) return;
      if (state.query != expectedQuery) return;

      _updateProviderIfCurrentRequest(
        providerId,
        requestToken,
        nextState.copyWith(isLoading: false, error: e.toString()),
        expectedQuery,
      );
    }
  }

  void _updateProviderIfCurrentQuery(
    String providerId,
    ProviderSearchState ps,
    String expectedQuery,
  ) {
    if (state.query != expectedQuery) return;

    state = state.copyWith(providers: {...state.providers, providerId: ps});
  }

  void _updateProviderIfCurrentRequest(
    String providerId,
    int requestToken,
    ProviderSearchState ps,
    String expectedQuery,
  ) {
    if (!_isCurrentRequest(providerId, requestToken)) return;
    if (state.query != expectedQuery) return;

    state = state.copyWith(providers: {...state.providers, providerId: ps});
  }

  /// Run the full search pipeline for one provider on one page:
  /// 1. POST search when no filters are active,
  /// 2. direct search when no filters are active,
  /// 3. GET via getSearchUrl (filter-aware).
  ///
  /// When filters are active, only the filter-aware GET path is allowed.
  Future<SearchResults?> _searchProviderOnce(
    ProviderInstance instance,
    Dio dio,
    String query,
    FilterValues filters,
    int page,
  ) {
    return searchProviderOnce(instance, dio, query, filters, page);
  }

  void clear() {
    // Invalidate all outstanding requests.
    for (final providerId in _requestTokens.keys.toList()) {
      _nextRequestToken(providerId);
    }

    state = const SearchState();
  }
}

// ═══════════════════════════════════════════════════════════
// Shared search pipeline
// ═══════════════════════════════════════════════════════════

/// Run the full search pipeline for one provider on one page:
/// 1. POST search (getSearchConfig) when filters are empty,
/// 2. direct search() when filters are empty,
/// 3. GET via getSearchUrl, which is filter-aware.
Future<SearchResults?> searchProviderOnce(
  ProviderInstance instance,
  Dio dio,
  String query,
  FilterValues filters,
  int page,
) async {
  Log.i(_tag, 'searchProviderOnce: query="$query" page=$page filters=$filters');

  // When filters are active, skip search paths that cannot receive them.
  final filtersActive = !filters.isEmpty;

  // 1. POST-based search
  //
  // The existing provider POST contract does not expose a filter argument,
  // so using it with active filters would silently ignore the user's
  // selection.
  if (!filtersActive && instance.hasFunction('getSearchConfig')) {
    Log.i(_tag, 'POST search: has getSearchConfig');

    try {
      final searchConfig = await instance.call('getSearchConfig', []);

      Log.i(_tag, 'POST search: config = $searchConfig');

      if (searchConfig is Map<String, dynamic>) {
        final results = await postSearch(
          instance,
          dio,
          searchConfig,
          query,
          page,
        );

        Log.i(_tag, 'POST search: results = ${results?.results.length}');

        if (results != null && results.results.isNotEmpty) {
          return results;
        }
      } else {
        Log.w(
          _tag,
          'POST search: getSearchConfig returned unexpected value: '
          '${searchConfig.runtimeType}',
        );
      }
    } catch (e) {
      Log.e(_tag, 'POST search threw', e);
    }
  } else if (!filtersActive) {
    Log.w(_tag, 'POST search: provider has no getSearchConfig');
  }

  // 2. Direct search function.
  //
  // This path cannot receive filters, so do not use it when filters
  // are active.
  if (!filtersActive) {
    final directResults = await instance.search(query, page);

    Log.i(_tag, 'Direct search: ${directResults?.results.length}');

    if (directResults != null && directResults.results.isNotEmpty) {
      return directResults;
    }
  }

  // 3. URL-based GET search.
  //
  // This is the filter-aware fallback and the only path used when
  // filters are active.
  final searchUrl = await instance.getSearchUrl(query, page, filters: filters);

  Log.i(_tag, 'GET search URL: $searchUrl');

  if (searchUrl == null || searchUrl.isEmpty) {
    return null;
  }

  Log.i(_tag, 'Fetching: $searchUrl');

  final response = await dio.get(searchUrl);
  final html = response.data.toString();

  Log.i(
    _tag,
    'GET search response: status=${response.statusCode} '
    'bytes=${html.length}',
  );

  final parsed = await instance.parseSearchResults(html);

  Log.i(
    _tag,
    'GET search parsed: ${parsed?.results.length} results, '
    'hasNextPage=${parsed?.hasNextPage}',
  );

  return parsed;
}

// ═══════════════════════════════════════════════════════════
// POST search
// ═══════════════════════════════════════════════════════════

/// Handle POST-based search.
///
/// The POST typically responds with a 3xx redirect to the results page.
/// Dio does not expose the final POST redirect as the result page when
/// redirect following is disabled, so the Location header is followed
/// manually with GET.
Future<SearchResults?> postSearch(
  ProviderInstance instance,
  Dio dio,
  Map<String, dynamic> config,
  String query,
  int page,
) async {
  try {
    final url = config['url'] as String?;
    final fields = config['fields'] as Map<String, dynamic>?;
    final headers = config['headers'] as Map<String, dynamic>?;
    final resultPattern = config['resultUrlPattern'] as String?;

    if (url == null || url.isEmpty) {
      Log.w(_tag, 'postSearch: config has no "url"');
      return null;
    }

    // Build form data from provider config.
    final formData = <String, String>{
      if (fields != null) ...fields.map((k, v) => MapEntry(k, v.toString())),
      'keyboard': query,
    };

    // Build headers from provider config.
    final requestHeaders = <String, String>{
      if (headers != null) ...headers.map((k, v) => MapEntry(k, v.toString())),
    };

    final formBody = formData.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}='
              '${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    Log.i(_tag, 'postSearch: POST $url bodyLength=${formBody.length}');

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

    final status = response.statusCode ?? 0;
    final location = response.headers.value('location');

    Log.i(
      _tag,
      'postSearch: status=$status '
      'hasLocation=${location != null && location.isNotEmpty}',
    );

    final isRedirect =
        status == 301 ||
        status == 302 ||
        status == 303 ||
        status == 307 ||
        status == 308;

    String? resultUrl;

    if (isRedirect) {
      // A redirect without Location cannot be followed safely.
      if (location == null || location.isEmpty) {
        Log.w(_tag, 'postSearch: redirect response has no Location header');

        // Do not attempt to manufacture a search ID from an empty
        // Location value. The normal search pipeline will continue
        // to the next search strategy.
        return null;
      }

      resultUrl = response.requestOptions.uri.resolve(location).toString();
    } else if (status == 200) {
      // Provider returned results directly.
      final html = response.data.toString();

      Log.i(_tag, 'postSearch: direct results page bytes=${html.length}');

      final parsed = await instance.parseSearchResults(html);

      Log.i(_tag, 'postSearch: parsed ${parsed?.results.length} results');

      return parsed;
    } else {
      Log.w(_tag, 'postSearch: unexpected status $status, aborting');
      return null;
    }

    // Optional URL pattern can still be used if the provider explicitly
    // gives one and the redirect target needs page substitution.
    if (resultUrl != null &&
        resultPattern != null &&
        resultPattern.isNotEmpty) {
      final resolvedPattern = resultPattern.replaceAll(
        '{page}',
        page.toString(),
      );

      if (resolvedPattern.isNotEmpty) {
        final patternUri = response.requestOptions.uri.resolve(resolvedPattern);

        // Only use the configured pattern when it appears to contain
        // the same provider-hosted search path. Otherwise keep the
        // actual redirect target.
        if (patternUri.host == response.requestOptions.uri.host) {
          // Keep the actual Location target by default. The pattern is
          // intentionally not allowed to override a concrete redirect
          // target without provider-specific evidence.
        }
      }
    }

    Log.i(_tag, 'postSearch: fetching results: $resultUrl');

    final resultResponse = await dio.get(resultUrl);
    final html = resultResponse.data.toString();

    Log.i(
      _tag,
      'postSearch: results page status=${resultResponse.statusCode} '
      'bytes=${html.length}',
    );

    final parsed = await instance.parseSearchResults(html);

    Log.i(_tag, 'postSearch: parsed ${parsed?.results.length} results');

    return parsed;
  } catch (e) {
    Log.e(_tag, 'POST search failed', e);
    return null;
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((
  ref,
) {
  return SearchNotifier(ref);
});
