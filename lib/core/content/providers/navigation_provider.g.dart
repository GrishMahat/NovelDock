// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'navigation_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ReaderNavigationNotifier)
final readerNavigationProvider = ReaderNavigationNotifierFamily._();

final class ReaderNavigationNotifierProvider
    extends $NotifierProvider<ReaderNavigationNotifier, ReaderNavigationState> {
  ReaderNavigationNotifierProvider._({
    required ReaderNavigationNotifierFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'readerNavigationProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$readerNavigationNotifierHash();

  @override
  String toString() {
    return r'readerNavigationProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReaderNavigationNotifier create() => ReaderNavigationNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReaderNavigationState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReaderNavigationState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReaderNavigationNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$readerNavigationNotifierHash() =>
    r'90292541870ed32ac193cf839dc4ade06f752494';

final class ReaderNavigationNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          ReaderNavigationNotifier,
          ReaderNavigationState,
          ReaderNavigationState,
          ReaderNavigationState,
          int
        > {
  ReaderNavigationNotifierFamily._()
    : super(
        retry: null,
        name: r'readerNavigationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  ReaderNavigationNotifierProvider call(int novelId) =>
      ReaderNavigationNotifierProvider._(argument: novelId, from: this);

  @override
  String toString() => r'readerNavigationProvider';
}

abstract class _$ReaderNavigationNotifier
    extends $Notifier<ReaderNavigationState> {
  late final _$args = ref.$arg as int;
  int get novelId => _$args;

  ReaderNavigationState build(int novelId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ReaderNavigationState, ReaderNavigationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ReaderNavigationState, ReaderNavigationState>,
              ReaderNavigationState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
