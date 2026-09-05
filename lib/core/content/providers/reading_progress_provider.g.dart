// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_progress_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ReadingProgressNotifier)
final readingProgressProvider = ReadingProgressNotifierFamily._();

final class ReadingProgressNotifierProvider
    extends $NotifierProvider<ReadingProgressNotifier, ReadingProgressState> {
  ReadingProgressNotifierProvider._({
    required ReadingProgressNotifierFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'readingProgressProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$readingProgressNotifierHash();

  @override
  String toString() {
    return r'readingProgressProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReadingProgressNotifier create() => ReadingProgressNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReadingProgressState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReadingProgressState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReadingProgressNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$readingProgressNotifierHash() =>
    r'7530617de7ec25cf39f0298f417ed5770831e807';

final class ReadingProgressNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          ReadingProgressNotifier,
          ReadingProgressState,
          ReadingProgressState,
          ReadingProgressState,
          int
        > {
  ReadingProgressNotifierFamily._()
    : super(
        retry: null,
        name: r'readingProgressProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  ReadingProgressNotifierProvider call(int novelId) =>
      ReadingProgressNotifierProvider._(argument: novelId, from: this);

  @override
  String toString() => r'readingProgressProvider';
}

abstract class _$ReadingProgressNotifier
    extends $Notifier<ReadingProgressState> {
  late final _$args = ref.$arg as int;
  int get novelId => _$args;

  ReadingProgressState build(int novelId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ReadingProgressState, ReadingProgressState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ReadingProgressState, ReadingProgressState>,
              ReadingProgressState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Provider to get all novels with their reading progress.
/// The only autoDispose provider in the app.

@ProviderFor(allReadingProgress)
final allReadingProgressProvider = AllReadingProgressProvider._();

/// Provider to get all novels with their reading progress.
/// The only autoDispose provider in the app.

final class AllReadingProgressProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<NovelProgress>>,
          List<NovelProgress>,
          FutureOr<List<NovelProgress>>
        >
    with
        $FutureModifier<List<NovelProgress>>,
        $FutureProvider<List<NovelProgress>> {
  /// Provider to get all novels with their reading progress.
  /// The only autoDispose provider in the app.
  AllReadingProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'allReadingProgressProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$allReadingProgressHash();

  @$internal
  @override
  $FutureProviderElement<List<NovelProgress>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<NovelProgress>> create(Ref ref) {
    return allReadingProgress(ref);
  }
}

String _$allReadingProgressHash() =>
    r'f3c51fd42125988497f30b3c542e04bdd1e190ea';
