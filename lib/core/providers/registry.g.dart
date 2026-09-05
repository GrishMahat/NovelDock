// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'registry.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for RegistryManager

@ProviderFor(registryManager)
final registryManagerProvider = RegistryManagerProvider._();

/// Provider for RegistryManager

final class RegistryManagerProvider
    extends
        $FunctionalProvider<
          AsyncValue<RegistryManager>,
          RegistryManager,
          FutureOr<RegistryManager>
        >
    with $FutureModifier<RegistryManager>, $FutureProvider<RegistryManager> {
  /// Provider for RegistryManager
  RegistryManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'registryManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$registryManagerHash();

  @$internal
  @override
  $FutureProviderElement<RegistryManager> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RegistryManager> create(Ref ref) {
    return registryManager(ref);
  }
}

String _$registryManagerHash() => r'2f8acce699e2d86373bc1586922758183710579b';
