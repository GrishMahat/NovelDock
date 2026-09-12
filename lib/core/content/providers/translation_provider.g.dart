// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chapterTranslation)
final chapterTranslationProvider = ChapterTranslationFamily._();

final class ChapterTranslationProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, FutureOr<String?>>
    with $FutureModifier<String?>, $FutureProvider<String?> {
  ChapterTranslationProvider._({
    required ChapterTranslationFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'chapterTranslationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chapterTranslationHash();

  @override
  String toString() {
    return r'chapterTranslationProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String?> create(Ref ref) {
    final argument = this.argument as int;
    return chapterTranslation(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChapterTranslationProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chapterTranslationHash() =>
    r'5be381c3493c72312e20d33ee8ab5b77da4f255e';

final class ChapterTranslationFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<String?>, int> {
  ChapterTranslationFamily._()
    : super(
        retry: null,
        name: r'chapterTranslationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ChapterTranslationProvider call(int chapterId) =>
      ChapterTranslationProvider._(argument: chapterId, from: this);

  @override
  String toString() => r'chapterTranslationProvider';
}
