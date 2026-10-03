// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'browse_cache_dao.dart';

// ignore_for_file: type=lint
mixin _$BrowseCacheDaoMixin on DatabaseAccessor<AppDatabase> {
  $BrowseCacheTable get browseCache => attachedDatabase.browseCache;
  BrowseCacheDaoManager get managers => BrowseCacheDaoManager(this);
}

class BrowseCacheDaoManager {
  final _$BrowseCacheDaoMixin _db;
  BrowseCacheDaoManager(this._db);
  $$BrowseCacheTableTableManager get browseCache =>
      $$BrowseCacheTableTableManager(_db.attachedDatabase, _db.browseCache);
}
