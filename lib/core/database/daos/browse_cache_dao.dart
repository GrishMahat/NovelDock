import 'dart:convert';

import 'package:drift/drift.dart';

import '../database.dart';

part 'browse_cache_dao.g.dart';

/// Cached result pages for the browse and in-source search tabs.
///
/// Entries are per page, not per query, so an infinite list can be served
/// fully from cache after the first visit. Freshness is two-tier: within
/// [freshWindow] the entry answers outright, past it the entry is still served
/// but reported stale so the caller can refresh behind the content.
@DriftAccessor(tables: [BrowseCache])
class BrowseCacheDao extends DatabaseAccessor<AppDatabase>
    with _$BrowseCacheDaoMixin {
  BrowseCacheDao(super.db);

  /// How long an entry answers without a network round trip.
  static const Duration freshWindow = Duration(minutes: 30);

  /// How long an entry survives at all. Bounds disk growth from long-tail
  /// filter combinations and endless scroll paging.
  static const Duration maxAge = Duration(days: 7);

  static String keyFor({
    required String providerId,
    required String mode,
    required String query,
    required String filterHash,
    required int page,
  }) => '$providerId|$mode|$query|$filterHash|$page';

  Future<void> putPage({
    required String providerId,
    required String mode,
    required String query,
    required String filterHash,
    required int page,
    required String payload,
    required int itemCount,
    Duration? freshFor,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return into(browseCache).insertOnConflictUpdate(
      BrowseCacheCompanion.insert(
        cacheKey: keyFor(
          providerId: providerId,
          mode: mode,
          query: query,
          filterHash: filterHash,
          page: page,
        ),
        providerId: providerId,
        mode: mode,
        query: Value(query),
        page: Value(page),
        payload: payload,
        itemCount: Value(itemCount),
        fetchedAt: now,
        staleAfter: now + (freshFor ?? freshWindow).inMilliseconds,
      ),
    );
  }

  Future<BrowseCacheData?> getPage({
    required String providerId,
    required String mode,
    required String query,
    required String filterHash,
    required int page,
  }) {
    return (select(browseCache)..where(
          (t) => t.cacheKey.equals(
            keyFor(
              providerId: providerId,
              mode: mode,
              query: query,
              filterHash: filterHash,
              page: page,
            ),
          ),
        ))
        .getSingleOrNull();
  }

  /// Drops entries older than [maxAge]. Cheap, index-backed, and safe to call
  /// opportunistically.
  Future<int> prune() {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - maxAge.inMilliseconds;
    return (delete(
      browseCache,
    )..where((t) => t.fetchedAt.isSmallerThanValue(cutoff))).go();
  }

  /// Clears every page for one provider. Called when a source is updated or
  /// removed, since its result shape may have changed underneath us.
  Future<int> clearProvider(String providerId) {
    return (delete(
      browseCache,
    )..where((t) => t.providerId.equals(providerId))).go();
  }

  /// Clears everything. Used by backup restore and "clear cache".
  Future<int> clearAll() => delete(browseCache).go();

  Future<int> count() async {
    final c = browseCache.cacheKey.count();
    final query = selectOnly(browseCache)..addColumns([c]);
    return (await query.getSingle()).read(c) ?? 0;
  }

  Future<int> totalBytes() async {
    final s = browseCache.payload.length.sum();
    final query = selectOnly(browseCache)..addColumns([s]);
    return (await query.getSingle()).read(s) ?? 0;
  }

  /// Decodes a stored payload. Returns null rather than throwing so a single
  /// corrupt entry cannot break a whole list.
  List<Map<String, dynamic>>? decode(BrowseCacheData row) {
    try {
      final decoded = jsonDecode(row.payload);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return null;
    }
  }
}
