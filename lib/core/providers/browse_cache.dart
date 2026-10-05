import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/browse_cache_dao.dart';
import '../providers/database_providers.dart';
import '../providers/engine.dart';
import '../providers/filters.dart';
import '../utils/logger.dart';

const _tag = 'BrowseCache';

/// Stable short hash of a provider's active filter values.
///
/// The cache key has to change when filters change, or "Latest" filtered by
/// genre would serve the unfiltered page. A full JSON dump would make keys
/// enormous, so this collapses it to 8 hex chars. FNV-1a: no dependency, and
/// collisions only ever cost a wrong-but-still-valid page for one filter
/// combination.
String filterFingerprint(FilterValues filters) {
  final json = jsonEncode(_sorted(filters.toJson()));
  var hash = 0x811c9dc5;
  for (final unit in json.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Recursively sorts map keys so key order in the source JSON cannot change
/// the fingerprint for the same logical filter set.
Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _sorted(value[k])};
  }
  if (value is List) return value.map(_sorted).toList();
  return value;
}

/// A cached result page plus whether it should be refreshed behind the
/// content.
class BrowsePageCacheEntry {
  final List<SearchResultItem> items;

  /// True when the entry is past its fresh window. The items are still worth
  /// showing; the caller revalidates instead of blocking on the network.
  final bool stale;

  const BrowsePageCacheEntry(this.items, {required this.stale});
}

/// Reads and writes cached browse/search pages.
class BrowseResultCache {
  final BrowseCacheDao _dao;

  /// Pruning is throttled: every write would otherwise walk the index on a
  /// long infinite scroll.
  DateTime? _lastPrune;

  BrowseResultCache(this._dao);

  static final provider = Provider<BrowseResultCache>(
    (ref) => BrowseResultCache(ref.watch(browseCacheDaoProvider)),
  );

  /// Cached page, or null when nothing usable is stored.
  Future<BrowsePageCacheEntry?> read({
    required String providerId,
    required String mode,
    required String query,
    required FilterValues filters,
    required int page,
  }) async {
    try {
      final row = await _dao.getPage(
        providerId: providerId,
        mode: mode,
        query: query,
        filterHash: filterFingerprint(filters),
        page: page,
      );
      if (row == null) return null;
      final decoded = _dao.decode(row);
      if (decoded == null) {
        // Corrupt payload: drop it rather than letting it fail every read.
        unawaited(
          _dao.clearProvider(providerId).then((_) {}).catchError((Object _) {}),
        );
        return null;
      }
      // Backfill providerId for entries written before toJson() persisted it.
      // Such items came from this provider's own cache key, so the id is known
      // here; rehydrating them makes the tapped row openable again instead of
      // silently aborting in _openNovel.
      var repaired = 0;
      final items = decoded.map((json) {
        final item = SearchResultItem.fromJson(json);
        if (item.providerId != null) return item;
        repaired++;
        return SearchResultItem(
          title: item.title,
          url: item.url,
          cover: item.cover,
          author: item.author,
          summary: item.summary,
          rating: item.rating,
          latestChapter: item.latestChapter,
          providerId: providerId,
          coverHeaders: item.coverHeaders,
        );
      }).toList();
      if (repaired > 0) {
        Log.i(
          _tag,
          'Backfilled providerId="$providerId" on $repaired cached item(s)',
        );
        unawaited(
          write(
            providerId: providerId,
            mode: mode,
            query: query,
            filters: filters,
            page: page,
            items: items,
          ).catchError((Object e) {
            Log.w(_tag, 'Could not persist repaired cache entry: $e');
          }),
        );
      }
      final stale = DateTime.now().millisecondsSinceEpoch > row.staleAfter;
      return BrowsePageCacheEntry(items, stale: stale);
    } catch (e) {
      // The cache is an optimization. A read failure must never surface as a
      // browse failure.
      Log.w(_tag, 'Cache read failed, falling through to network: $e');
      return null;
    }
  }

  Future<void> write({
    required String providerId,
    required String mode,
    required String query,
    required FilterValues filters,
    required int page,
    required List<SearchResultItem> items,
  }) async {
    try {
      await _dao.putPage(
        providerId: providerId,
        mode: mode,
        query: query,
        filterHash: filterFingerprint(filters),
        page: page,
        payload: jsonEncode(items.map((e) => e.toJson()).toList()),
        itemCount: items.length,
      );
      _maybePrune();
    } catch (e) {
      Log.w(_tag, 'Cache write failed: $e');
    }
  }

  void _maybePrune() {
    final last = _lastPrune;
    final now = DateTime.now();
    if (last != null && now.difference(last) < const Duration(hours: 6)) {
      return;
    }
    _lastPrune = now;
    unawaited(_dao.prune().then((_) {}).catchError((Object _) {}));
  }

  /// Drops a source's cached pages. Called when a provider is updated or
  /// removed, since its result shape may have changed underneath us.
  Future<void> invalidateProvider(String providerId) async {
    try {
      await _dao.clearProvider(providerId);
    } catch (e) {
      Log.w(_tag, 'Could not invalidate $providerId: $e');
    }
  }

  Future<void> clear() async {
    try {
      await _dao.clearAll();
    } catch (e) {
      Log.w(_tag, 'Could not clear browse cache: $e');
    }
  }

  Future<int> entryCount() async {
    try {
      return await _dao.count();
    } catch (_) {
      return 0;
    }
  }

  Future<int> sizeBytes() async {
    try {
      return await _dao.totalBytes();
    } catch (_) {
      return 0;
    }
  }
}
