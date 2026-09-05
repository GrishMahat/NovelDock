// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_settings_page.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TranslationSettingsNotifier)
final translationSettingsProvider = TranslationSettingsNotifierProvider._();

final class TranslationSettingsNotifierProvider
    extends
        $NotifierProvider<TranslationSettingsNotifier, TranslationSettings> {
  TranslationSettingsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationSettingsNotifierHash();

  @$internal
  @override
  TranslationSettingsNotifier create() => TranslationSettingsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationSettings>(value),
    );
  }
}

String _$translationSettingsNotifierHash() =>
    r'167fae5351acb01a549b8d8caea665796936bfc9';

abstract class _$TranslationSettingsNotifier
    extends $Notifier<TranslationSettings> {
  TranslationSettings build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TranslationSettings, TranslationSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TranslationSettings, TranslationSettings>,
              TranslationSettings,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
