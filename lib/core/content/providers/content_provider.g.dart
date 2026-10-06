// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'content_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ContentNotifier)
final contentProvider = ContentNotifierProvider._();

final class ContentNotifierProvider
    extends $NotifierProvider<ContentNotifier, ContentState> {
  ContentNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'contentProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contentNotifierHash();

  @$internal
  @override
  ContentNotifier create() => ContentNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ContentState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ContentState>(value),
    );
  }
}

String _$contentNotifierHash() => r'a208fd2ca5d91c3b33055b5a1758c16596a4700c';

abstract class _$ContentNotifier extends $Notifier<ContentState> {
  ContentState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ContentState, ContentState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ContentState, ContentState>,
              ContentState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
