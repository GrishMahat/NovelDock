// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(translationService)
final translationServiceProvider = TranslationServiceProvider._();

final class TranslationServiceProvider
    extends
        $FunctionalProvider<
          TranslationService,
          TranslationService,
          TranslationService
        >
    with $Provider<TranslationService> {
  TranslationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationServiceHash();

  @$internal
  @override
  $ProviderElement<TranslationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TranslationService create(Ref ref) {
    return translationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TranslationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TranslationService>(value),
    );
  }
}

String _$translationServiceHash() =>
    r'65aca261f644d8d980a8bd83d9799aed6b8cebb0';
