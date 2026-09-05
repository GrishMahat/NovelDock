// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_settings_page.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DownloadSettingsNotifier)
final downloadSettingsProvider = DownloadSettingsNotifierProvider._();

final class DownloadSettingsNotifierProvider
    extends $NotifierProvider<DownloadSettingsNotifier, DownloadSettings> {
  DownloadSettingsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'downloadSettingsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadSettingsNotifierHash();

  @$internal
  @override
  DownloadSettingsNotifier create() => DownloadSettingsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DownloadSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DownloadSettings>(value),
    );
  }
}

String _$downloadSettingsNotifierHash() =>
    r'f74126baa737d287f724de2dff07f33a163ad9ba';

abstract class _$DownloadSettingsNotifier extends $Notifier<DownloadSettings> {
  DownloadSettings build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DownloadSettings, DownloadSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DownloadSettings, DownloadSettings>,
              DownloadSettings,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
