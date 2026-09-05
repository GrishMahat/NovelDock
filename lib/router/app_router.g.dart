// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_router.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Routes nested under the shell (rail/top bar visible on desktop) are listed
/// first; routes that must stay full-screen (e.g. the immersive reader) sit at
/// the root navigator level.

@ProviderFor(router)
final routerProvider = RouterProvider._();

/// Routes nested under the shell (rail/top bar visible on desktop) are listed
/// first; routes that must stay full-screen (e.g. the immersive reader) sit at
/// the root navigator level.

final class RouterProvider
    extends $FunctionalProvider<GoRouter, GoRouter, GoRouter>
    with $Provider<GoRouter> {
  /// Routes nested under the shell (rail/top bar visible on desktop) are listed
  /// first; routes that must stay full-screen (e.g. the immersive reader) sit at
  /// the root navigator level.
  RouterProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routerHash();

  @$internal
  @override
  $ProviderElement<GoRouter> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GoRouter create(Ref ref) {
    return router(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GoRouter value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GoRouter>(value),
    );
  }
}

String _$routerHash() => r'21e15962537d31337e8a5041ff317e2b9b3e2b24';
