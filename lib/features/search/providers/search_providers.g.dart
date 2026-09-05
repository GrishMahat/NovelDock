// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SearchHistoryNotifier)
final searchHistoryProvider = SearchHistoryNotifierProvider._();

final class SearchHistoryNotifierProvider
    extends $NotifierProvider<SearchHistoryNotifier, List<String>> {
  SearchHistoryNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchHistoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchHistoryNotifierHash();

  @$internal
  @override
  SearchHistoryNotifier create() => SearchHistoryNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<String>>(value),
    );
  }
}

String _$searchHistoryNotifierHash() =>
    r'13a3157a9488c743d69040acbdbf3babf616e010';

abstract class _$SearchHistoryNotifier extends $Notifier<List<String>> {
  List<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<String>, List<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<String>, List<String>>,
              List<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Which providers participate in global search.
///
/// Before the user explicitly chooses providers, all enabled providers
/// participate. Once the user explicitly chooses, the exact selected set
/// is respected, including an intentionally empty set.

@ProviderFor(SearchProviderSelectionNotifier)
final searchProviderSelectionProvider =
    SearchProviderSelectionNotifierProvider._();

/// Which providers participate in global search.
///
/// Before the user explicitly chooses providers, all enabled providers
/// participate. Once the user explicitly chooses, the exact selected set
/// is respected, including an intentionally empty set.
final class SearchProviderSelectionNotifierProvider
    extends $NotifierProvider<SearchProviderSelectionNotifier, Set<String>> {
  /// Which providers participate in global search.
  ///
  /// Before the user explicitly chooses providers, all enabled providers
  /// participate. Once the user explicitly chooses, the exact selected set
  /// is respected, including an intentionally empty set.
  SearchProviderSelectionNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchProviderSelectionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchProviderSelectionNotifierHash();

  @$internal
  @override
  SearchProviderSelectionNotifier create() => SearchProviderSelectionNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$searchProviderSelectionNotifierHash() =>
    r'adcfa278088dd4c09359ff53528ceba25d366326';

/// Which providers participate in global search.
///
/// Before the user explicitly chooses providers, all enabled providers
/// participate. Once the user explicitly chooses, the exact selected set
/// is respected, including an intentionally empty set.

abstract class _$SearchProviderSelectionNotifier
    extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(SearchNotifier)
final searchProvider = SearchNotifierProvider._();

final class SearchNotifierProvider
    extends $NotifierProvider<SearchNotifier, SearchState> {
  SearchNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'searchProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$searchNotifierHash();

  @$internal
  @override
  SearchNotifier create() => SearchNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SearchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SearchState>(value),
    );
  }
}

String _$searchNotifierHash() => r'85d24105462d7ba2db113e0e5a46d6367723d302';

abstract class _$SearchNotifier extends $Notifier<SearchState> {
  SearchState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SearchState, SearchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SearchState, SearchState>,
              SearchState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
