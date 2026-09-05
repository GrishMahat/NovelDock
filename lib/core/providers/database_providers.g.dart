// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Database instance provider

@ProviderFor(appDatabase)
final appDatabaseProvider = AppDatabaseProvider._();

/// Database instance provider

final class AppDatabaseProvider
    extends $FunctionalProvider<AppDatabase, AppDatabase, AppDatabase>
    with $Provider<AppDatabase> {
  /// Database instance provider
  AppDatabaseProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appDatabaseProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appDatabaseHash();

  @$internal
  @override
  $ProviderElement<AppDatabase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppDatabase create(Ref ref) {
    return appDatabase(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppDatabase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppDatabase>(value),
    );
  }
}

String _$appDatabaseHash() => r'abb0f273bf515fd333bc44fa6ceb43d83ed3896f';

/// DAO providers

@ProviderFor(novelDao)
final novelDaoProvider = NovelDaoProvider._();

/// DAO providers

final class NovelDaoProvider
    extends $FunctionalProvider<NovelDao, NovelDao, NovelDao>
    with $Provider<NovelDao> {
  /// DAO providers
  NovelDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'novelDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$novelDaoHash();

  @$internal
  @override
  $ProviderElement<NovelDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NovelDao create(Ref ref) {
    return novelDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NovelDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NovelDao>(value),
    );
  }
}

String _$novelDaoHash() => r'cb53f6ae6697c531c3df68ece14f647050afe1ec';

@ProviderFor(chapterDao)
final chapterDaoProvider = ChapterDaoProvider._();

final class ChapterDaoProvider
    extends $FunctionalProvider<ChapterDao, ChapterDao, ChapterDao>
    with $Provider<ChapterDao> {
  ChapterDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chapterDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chapterDaoHash();

  @$internal
  @override
  $ProviderElement<ChapterDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ChapterDao create(Ref ref) {
    return chapterDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChapterDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChapterDao>(value),
    );
  }
}

String _$chapterDaoHash() => r'eb8a000c09d3e7e982b614c05da0977420495edc';

@ProviderFor(libraryDao)
final libraryDaoProvider = LibraryDaoProvider._();

final class LibraryDaoProvider
    extends $FunctionalProvider<LibraryDao, LibraryDao, LibraryDao>
    with $Provider<LibraryDao> {
  LibraryDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libraryDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libraryDaoHash();

  @$internal
  @override
  $ProviderElement<LibraryDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LibraryDao create(Ref ref) {
    return libraryDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LibraryDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LibraryDao>(value),
    );
  }
}

String _$libraryDaoHash() => r'6d80fd8b15902439d3a35ac44efd70ea8e052c27';

@ProviderFor(historyDao)
final historyDaoProvider = HistoryDaoProvider._();

final class HistoryDaoProvider
    extends $FunctionalProvider<HistoryDao, HistoryDao, HistoryDao>
    with $Provider<HistoryDao> {
  HistoryDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'historyDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyDaoHash();

  @$internal
  @override
  $ProviderElement<HistoryDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HistoryDao create(Ref ref) {
    return historyDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HistoryDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HistoryDao>(value),
    );
  }
}

String _$historyDaoHash() => r'67aa25520220795ca582dc6bf8e8a62d3a5a8576';

@ProviderFor(downloadDao)
final downloadDaoProvider = DownloadDaoProvider._();

final class DownloadDaoProvider
    extends $FunctionalProvider<DownloadDao, DownloadDao, DownloadDao>
    with $Provider<DownloadDao> {
  DownloadDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'downloadDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$downloadDaoHash();

  @$internal
  @override
  $ProviderElement<DownloadDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DownloadDao create(Ref ref) {
    return downloadDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DownloadDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DownloadDao>(value),
    );
  }
}

String _$downloadDaoHash() => r'7c377fc16007f46532a902c97e591172edab5d2c';

@ProviderFor(bookmarkDao)
final bookmarkDaoProvider = BookmarkDaoProvider._();

final class BookmarkDaoProvider
    extends $FunctionalProvider<BookmarkDao, BookmarkDao, BookmarkDao>
    with $Provider<BookmarkDao> {
  BookmarkDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bookmarkDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bookmarkDaoHash();

  @$internal
  @override
  $ProviderElement<BookmarkDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BookmarkDao create(Ref ref) {
    return bookmarkDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BookmarkDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BookmarkDao>(value),
    );
  }
}

String _$bookmarkDaoHash() => r'36dd1a3f2b03851dd4ef3c09f14edd5bb21c0853';

@ProviderFor(settingsDao)
final settingsDaoProvider = SettingsDaoProvider._();

final class SettingsDaoProvider
    extends $FunctionalProvider<SettingsDao, SettingsDao, SettingsDao>
    with $Provider<SettingsDao> {
  SettingsDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsDaoHash();

  @$internal
  @override
  $ProviderElement<SettingsDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SettingsDao create(Ref ref) {
    return settingsDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsDao>(value),
    );
  }
}

String _$settingsDaoHash() => r'b30250ebab9c676c06089cfa66a65ae8e24456db';

@ProviderFor(providerCacheDao)
final providerCacheDaoProvider = ProviderCacheDaoProvider._();

final class ProviderCacheDaoProvider
    extends
        $FunctionalProvider<
          ProviderCacheDao,
          ProviderCacheDao,
          ProviderCacheDao
        >
    with $Provider<ProviderCacheDao> {
  ProviderCacheDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'providerCacheDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$providerCacheDaoHash();

  @$internal
  @override
  $ProviderElement<ProviderCacheDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ProviderCacheDao create(Ref ref) {
    return providerCacheDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProviderCacheDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProviderCacheDao>(value),
    );
  }
}

String _$providerCacheDaoHash() => r'0d384042f83fc24c0dcdd7cf98bde2df3e089fdc';

@ProviderFor(novelProgressDao)
final novelProgressDaoProvider = NovelProgressDaoProvider._();

final class NovelProgressDaoProvider
    extends
        $FunctionalProvider<
          NovelProgressDao,
          NovelProgressDao,
          NovelProgressDao
        >
    with $Provider<NovelProgressDao> {
  NovelProgressDaoProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'novelProgressDaoProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$novelProgressDaoHash();

  @$internal
  @override
  $ProviderElement<NovelProgressDao> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NovelProgressDao create(Ref ref) {
    return novelProgressDao(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NovelProgressDao value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NovelProgressDao>(value),
    );
  }
}

String _$novelProgressDaoHash() => r'b1da697a7830afcbd00981437f07dec9a130a6fe';
