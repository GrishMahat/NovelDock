// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'novel_fetch_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(NovelFetchStateNotifier)
final novelFetchStateProvider = NovelFetchStateNotifierFamily._();

final class NovelFetchStateNotifierProvider
    extends $NotifierProvider<NovelFetchStateNotifier, NovelFetchState> {
  NovelFetchStateNotifierProvider._({
    required NovelFetchStateNotifierFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'novelFetchStateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$novelFetchStateNotifierHash();

  @override
  String toString() {
    return r'novelFetchStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  NovelFetchStateNotifier create() => NovelFetchStateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NovelFetchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NovelFetchState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NovelFetchStateNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$novelFetchStateNotifierHash() =>
    r'7280af6ca183f58863608e2f465a342ce1dd426e';

final class NovelFetchStateNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          NovelFetchStateNotifier,
          NovelFetchState,
          NovelFetchState,
          NovelFetchState,
          int
        > {
  NovelFetchStateNotifierFamily._()
    : super(
        retry: null,
        name: r'novelFetchStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  NovelFetchStateNotifierProvider call(int novelId) =>
      NovelFetchStateNotifierProvider._(argument: novelId, from: this);

  @override
  String toString() => r'novelFetchStateProvider';
}

abstract class _$NovelFetchStateNotifier extends $Notifier<NovelFetchState> {
  late final _$args = ref.$arg as int;
  int get novelId => _$args;

  NovelFetchState build(int novelId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<NovelFetchState, NovelFetchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<NovelFetchState, NovelFetchState>,
              NovelFetchState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
