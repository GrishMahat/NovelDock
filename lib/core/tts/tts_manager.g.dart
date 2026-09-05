// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tts_manager.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TtsManager)
final ttsManagerProvider = TtsManagerProvider._();

final class TtsManagerProvider
    extends $NotifierProvider<TtsManager, TtsManagerState> {
  TtsManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ttsManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ttsManagerHash();

  @$internal
  @override
  TtsManager create() => TtsManager();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TtsManagerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TtsManagerState>(value),
    );
  }
}

String _$ttsManagerHash() => r'5c405f9d0e7612fe9655f0383223ddc352c4ec7b';

abstract class _$TtsManager extends $Notifier<TtsManagerState> {
  TtsManagerState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TtsManagerState, TtsManagerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TtsManagerState, TtsManagerState>,
              TtsManagerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
