// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_cache_dao.dart';

// ignore_for_file: type=lint
mixin _$ProviderCacheDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProviderCacheTable get providerCache => attachedDatabase.providerCache;
  ProviderCacheDaoManager get managers => ProviderCacheDaoManager(this);
}

class ProviderCacheDaoManager {
  final _$ProviderCacheDaoMixin _db;
  ProviderCacheDaoManager(this._db);
  $$ProviderCacheTableTableManager get providerCache =>
      $$ProviderCacheTableTableManager(_db.attachedDatabase, _db.providerCache);
}
