// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'novel_opener.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider-scoped [NovelOpener]. Use `ref.read(novelOpenerProvider)` from
/// widgets instead of constructing one with a [WidgetRef] — the background
/// fetch outlives the originating screen.

@ProviderFor(novelOpener)
final novelOpenerProvider = NovelOpenerProvider._();

/// Provider-scoped [NovelOpener]. Use `ref.read(novelOpenerProvider)` from
/// widgets instead of constructing one with a [WidgetRef] — the background
/// fetch outlives the originating screen.

final class NovelOpenerProvider
    extends $FunctionalProvider<NovelOpener, NovelOpener, NovelOpener>
    with $Provider<NovelOpener> {
  /// Provider-scoped [NovelOpener]. Use `ref.read(novelOpenerProvider)` from
  /// widgets instead of constructing one with a [WidgetRef] — the background
  /// fetch outlives the originating screen.
  NovelOpenerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'novelOpenerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$novelOpenerHash();

  @$internal
  @override
  $ProviderElement<NovelOpener> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NovelOpener create(Ref ref) {
    return novelOpener(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NovelOpener value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NovelOpener>(value),
    );
  }
}

String _$novelOpenerHash() => r'01b0193f32e2a3be83f6e9dda09ab2c6f63bd2f4';
