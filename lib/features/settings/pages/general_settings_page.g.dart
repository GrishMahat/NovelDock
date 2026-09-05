// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'general_settings_page.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(GeneralSettingsNotifier)
final generalSettingsProvider = GeneralSettingsNotifierProvider._();

final class GeneralSettingsNotifierProvider
    extends $NotifierProvider<GeneralSettingsNotifier, GeneralSettings> {
  GeneralSettingsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generalSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generalSettingsNotifierHash();

  @$internal
  @override
  GeneralSettingsNotifier create() => GeneralSettingsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GeneralSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GeneralSettings>(value),
    );
  }
}

String _$generalSettingsNotifierHash() =>
    r'dc801ddcf59100a67c118b46baa96e35fb8dda87';

abstract class _$GeneralSettingsNotifier extends $Notifier<GeneralSettings> {
  GeneralSettings build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<GeneralSettings, GeneralSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<GeneralSettings, GeneralSettings>,
              GeneralSettings,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
