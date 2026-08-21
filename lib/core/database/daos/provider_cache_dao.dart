import 'package:drift/drift.dart';

import '../database.dart';

part 'provider_cache_dao.g.dart';

@DriftAccessor(tables: [ProviderCache])
class ProviderCacheDao extends DatabaseAccessor<AppDatabase>
    with _$ProviderCacheDaoMixin {
  ProviderCacheDao(super.db);

  Future<int> insertOrUpdateProvider(ProviderCacheCompanion provider) {
    return into(
      providerCache,
    ).insert(provider, mode: InsertMode.insertOrReplace);
  }

  Future<void> updateProvider(
    String id, {
    String? version,
    String? jsSource,
    bool? enabled,
  }) async {
    final companion = ProviderCacheCompanion(
      version: version != null ? Value(version) : const Value.absent(),
      jsSource: jsSource != null ? Value(jsSource) : const Value.absent(),
      enabled: enabled != null ? Value(enabled) : const Value.absent(),
      lastUpdated: Value(DateTime.now().millisecondsSinceEpoch),
    );
    await (update(
      providerCache,
    )..where((t) => t.id.equals(id))).write(companion);
  }

  Future<void> deleteProvider(String id) async {
    await (delete(providerCache)..where((t) => t.id.equals(id))).go();
  }

  Future<ProviderCacheData?> getProviderById(String id) {
    return (select(
      providerCache,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<List<ProviderCacheData>> getAllProviders() {
    return select(providerCache).get();
  }

  Stream<List<ProviderCacheData>> watchAllProviders() {
    return select(providerCache).watch();
  }

  Future<List<ProviderCacheData>> getEnabledProviders() {
    return (select(providerCache)..where((t) => t.enabled.equals(true))).get();
  }

  Stream<List<ProviderCacheData>> watchEnabledProviders() {
    return (select(
      providerCache,
    )..where((t) => t.enabled.equals(true))).watch();
  }

  Future<void> setProviderEnabled(String id, bool enabled) async {
    await (update(providerCache)..where((t) => t.id.equals(id))).write(
      ProviderCacheCompanion(enabled: Value(enabled)),
    );
  }
}
