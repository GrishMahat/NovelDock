// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_management_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// List of registries the user has added — persisted to settings DB.

@ProviderFor(RegistriesNotifier)
final registriesProvider = RegistriesNotifierProvider._();

/// List of registries the user has added — persisted to settings DB.
final class RegistriesNotifierProvider
    extends $AsyncNotifierProvider<RegistriesNotifier, List<RegistryInfo>> {
  /// List of registries the user has added — persisted to settings DB.
  RegistriesNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'registriesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$registriesNotifierHash();

  @$internal
  @override
  RegistriesNotifier create() => RegistriesNotifier();
}

String _$registriesNotifierHash() =>
    r'ef12f18e9e6cad7a7db113a09f88a85934f8d1cb';

/// List of registries the user has added — persisted to settings DB.

abstract class _$RegistriesNotifier extends $AsyncNotifier<List<RegistryInfo>> {
  FutureOr<List<RegistryInfo>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<RegistryInfo>>, List<RegistryInfo>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<RegistryInfo>>, List<RegistryInfo>>,
              AsyncValue<List<RegistryInfo>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// All available providers — from enabled registries only.

@ProviderFor(availableProviders)
final availableProvidersProvider = AvailableProvidersProvider._();

/// All available providers — from enabled registries only.

final class AvailableProvidersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ProviderMeta>>,
          List<ProviderMeta>,
          FutureOr<List<ProviderMeta>>
        >
    with
        $FutureModifier<List<ProviderMeta>>,
        $FutureProvider<List<ProviderMeta>> {
  /// All available providers — from enabled registries only.
  AvailableProvidersProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableProvidersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableProvidersHash();

  @$internal
  @override
  $FutureProviderElement<List<ProviderMeta>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ProviderMeta>> create(Ref ref) {
    return availableProviders(ref);
  }
}

String _$availableProvidersHash() =>
    r'd247b67668e26fa288c09fade6ae241068964f19';

/// Set of enabled provider IDs — persisted to settings table.

@ProviderFor(EnabledProvidersNotifier)
final enabledProvidersProvider = EnabledProvidersNotifierProvider._();

/// Set of enabled provider IDs — persisted to settings table.
final class EnabledProvidersNotifierProvider
    extends $NotifierProvider<EnabledProvidersNotifier, Set<String>> {
  /// Set of enabled provider IDs — persisted to settings table.
  EnabledProvidersNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'enabledProvidersProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$enabledProvidersNotifierHash();

  @$internal
  @override
  EnabledProvidersNotifier create() => EnabledProvidersNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$enabledProvidersNotifierHash() =>
    r'2f31c5419c639042160d10d8ca40f50f12ace82a';

/// Set of enabled provider IDs — persisted to settings table.

abstract class _$EnabledProvidersNotifier extends $Notifier<Set<String>> {
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
