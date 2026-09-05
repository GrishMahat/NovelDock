// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_prefs.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Synchronous handle to the app-wide SharedPreferences instance.
///
/// `main()` awaits the instance before `runApp` and overrides this provider
/// with it, so settings notifiers and the router read persisted values before
/// the first frame instead of flashing defaults and re-rendering.

@ProviderFor(appPrefs)
final appPrefsProvider = AppPrefsProvider._();

/// Synchronous handle to the app-wide SharedPreferences instance.
///
/// `main()` awaits the instance before `runApp` and overrides this provider
/// with it, so settings notifiers and the router read persisted values before
/// the first frame instead of flashing defaults and re-rendering.

final class AppPrefsProvider
    extends
        $FunctionalProvider<
          SharedPreferences,
          SharedPreferences,
          SharedPreferences
        >
    with $Provider<SharedPreferences> {
  /// Synchronous handle to the app-wide SharedPreferences instance.
  ///
  /// `main()` awaits the instance before `runApp` and overrides this provider
  /// with it, so settings notifiers and the router read persisted values before
  /// the first frame instead of flashing defaults and re-rendering.
  AppPrefsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appPrefsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appPrefsHash();

  @$internal
  @override
  $ProviderElement<SharedPreferences> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SharedPreferences create(Ref ref) {
    return appPrefs(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SharedPreferences value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SharedPreferences>(value),
    );
  }
}

String _$appPrefsHash() => r'2e91313e2ba8d2a34b977e9fda0af2f4bba5904d';

/// Resolved application documents directory.
///
/// Overridden in `main()` like [appPrefsProvider] so download settings can
/// compute their default path synchronously.

@ProviderFor(appDocumentsDir)
final appDocumentsDirProvider = AppDocumentsDirProvider._();

/// Resolved application documents directory.
///
/// Overridden in `main()` like [appPrefsProvider] so download settings can
/// compute their default path synchronously.

final class AppDocumentsDirProvider
    extends $FunctionalProvider<Directory, Directory, Directory>
    with $Provider<Directory> {
  /// Resolved application documents directory.
  ///
  /// Overridden in `main()` like [appPrefsProvider] so download settings can
  /// compute their default path synchronously.
  AppDocumentsDirProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDocumentsDirProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDocumentsDirHash();

  @$internal
  @override
  $ProviderElement<Directory> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Directory create(Ref ref) {
    return appDocumentsDir(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Directory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Directory>(value),
    );
  }
}

String _$appDocumentsDirHash() => r'82388663411e573bc20937d96de8e4245f05a1c6';
