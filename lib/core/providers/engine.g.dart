// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'engine.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(providerEngine)
final providerEngineProvider = ProviderEngineProvider._();

final class ProviderEngineProvider
    extends $FunctionalProvider<ProviderEngine, ProviderEngine, ProviderEngine>
    with $Provider<ProviderEngine> {
  ProviderEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'providerEngineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$providerEngineHash();

  @$internal
  @override
  $ProviderElement<ProviderEngine> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProviderEngine create(Ref ref) {
    return providerEngine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProviderEngine value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProviderEngine>(value),
    );
  }
}

String _$providerEngineHash() => r'7091a19be5fbab5848ba196430d84af528dfaca1';

/// Loads a provider's JS, evaluates it, and loads its feature flags.
///
/// This is the single load path for provider instances. Callers just
/// `ref.read(providerInstanceProvider(id).future)`. The family caches per
/// provider id, so concurrent callers share one load. After a registry
/// update or removal, invalidate the family to force a fresh instance.

@ProviderFor(providerInstance)
final providerInstanceProvider = ProviderInstanceFamily._();

/// Loads a provider's JS, evaluates it, and loads its feature flags.
///
/// This is the single load path for provider instances. Callers just
/// `ref.read(providerInstanceProvider(id).future)`. The family caches per
/// provider id, so concurrent callers share one load. After a registry
/// update or removal, invalidate the family to force a fresh instance.

final class ProviderInstanceProvider
    extends
        $FunctionalProvider<
          AsyncValue<ProviderInstance?>,
          ProviderInstance?,
          FutureOr<ProviderInstance?>
        >
    with
        $FutureModifier<ProviderInstance?>,
        $FutureProvider<ProviderInstance?> {
  /// Loads a provider's JS, evaluates it, and loads its feature flags.
  ///
  /// This is the single load path for provider instances. Callers just
  /// `ref.read(providerInstanceProvider(id).future)`. The family caches per
  /// provider id, so concurrent callers share one load. After a registry
  /// update or removal, invalidate the family to force a fresh instance.
  ProviderInstanceProvider._({
    required ProviderInstanceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'providerInstanceProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$providerInstanceHash();

  @override
  String toString() {
    return r'providerInstanceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ProviderInstance?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ProviderInstance?> create(Ref ref) {
    final argument = this.argument as String;
    return providerInstance(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProviderInstanceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$providerInstanceHash() => r'5d74ebc867158872021ae13e9f02c087b5422ebc';

/// Loads a provider's JS, evaluates it, and loads its feature flags.
///
/// This is the single load path for provider instances. Callers just
/// `ref.read(providerInstanceProvider(id).future)`. The family caches per
/// provider id, so concurrent callers share one load. After a registry
/// update or removal, invalidate the family to force a fresh instance.

final class ProviderInstanceFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ProviderInstance?>, String> {
  ProviderInstanceFamily._()
    : super(
        retry: null,
        name: r'providerInstanceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Loads a provider's JS, evaluates it, and loads its feature flags.
  ///
  /// This is the single load path for provider instances. Callers just
  /// `ref.read(providerInstanceProvider(id).future)`. The family caches per
  /// provider id, so concurrent callers share one load. After a registry
  /// update or removal, invalidate the family to force a fresh instance.

  ProviderInstanceProvider call(String providerId) =>
      ProviderInstanceProvider._(argument: providerId, from: this);

  @override
  String toString() => r'providerInstanceProvider';
}
