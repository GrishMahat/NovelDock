// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DownloadNotifier)
final downloadProvider = DownloadNotifierProvider._();

final class DownloadNotifierProvider
    extends
        $NotifierProvider<DownloadNotifier, Map<int, NovelDownloadProgress>> {
  DownloadNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'downloadProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadNotifierHash();

  @$internal
  @override
  DownloadNotifier create() => DownloadNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<int, NovelDownloadProgress> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<int, NovelDownloadProgress>>(
        value,
      ),
    );
  }
}

String _$downloadNotifierHash() => r'2b9d1b80652bb571c610d1b22172d5a838605bde';

abstract class _$DownloadNotifier
    extends $Notifier<Map<int, NovelDownloadProgress>> {
  Map<int, NovelDownloadProgress> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<int, NovelDownloadProgress>,
              Map<int, NovelDownloadProgress>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<int, NovelDownloadProgress>,
                Map<int, NovelDownloadProgress>
              >,
              Map<int, NovelDownloadProgress>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
