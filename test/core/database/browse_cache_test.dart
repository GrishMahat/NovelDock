// Covers the browse result cache added because every visit to a source was a
// cold network fetch plus HTML parse. The riskiest part is the cache key: a
// collision or an unstable fingerprint would serve the wrong page for a
// filter combination, which is worse than no cache at all.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/database/database.dart';
import 'package:noveldock/core/providers/browse_cache.dart';
import 'package:noveldock/core/providers/engine.dart';
import 'package:noveldock/core/providers/filters.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  BrowseResultCache cache() => BrowseResultCache(db.browseCacheDao);

  Future<void> writeFreshEntry(AppDatabase db) => db.browseCacheDao.putPage(
    providerId: 'fresh',
    mode: 'popular',
    query: '',
    filterHash: filterFingerprint(const FilterValues()),
    page: 1,
    payload: '[]',
    itemCount: 0,
  );

  List<SearchResultItem> items(int n, {String prefix = 'novel'}) => [
    for (var i = 0; i < n; i++)
      SearchResultItem(
        title: '$prefix $i',
        url: 'https://example.com/$prefix/$i',
        author: 'Author $i',
        cover: 'https://example.com/c/$i.jpg',
        latestChapter: 'Chapter $i',
        rating: 500 + i,
        coverHeaders: const {'Referer': 'https://example.com'},
      ),
  ];

  group('filter fingerprint', () {
    test('is stable across map key order', () {
      final a = FilterValues({'genre': 'Fantasy', 'page': 1});
      final b = FilterValues({'page': 1, 'genre': 'Fantasy'});
      expect(filterFingerprint(a), filterFingerprint(b));
    });

    test('differs when any value changes', () {
      final base = FilterValues({'genre': 'Fantasy'});
      expect(
        filterFingerprint(base),
        isNot(filterFingerprint(FilterValues({'genre': 'Horror'}))),
      );
    });

    test('differs when a key is added', () {
      final a = FilterValues({'genre': 'Fantasy'});
      final b = FilterValues({'genre': 'Fantasy', 'status': 'Ongoing'});
      expect(filterFingerprint(a), isNot(filterFingerprint(b)));
    });

    test('nested list order is significant', () {
      final a = FilterValues({
        'tags': ['x', 'y'],
      });
      final b = FilterValues({
        'tags': ['y', 'x'],
      });
      expect(filterFingerprint(a), isNot(filterFingerprint(b)));
    });

    test('empty filters hash consistently', () {
      expect(
        filterFingerprint(const FilterValues()),
        filterFingerprint(FilterValues({})),
      );
    });
  });

  group('round trip', () {
    test('writes then reads back every field', () async {
      final c = cache();
      final original = items(3);

      await c.write(
        providerId: 'wuxia',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
        items: original,
      );

      final entry = await c.read(
        providerId: 'wuxia',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
      );

      expect(entry, isNotNull);
      expect(entry!.items.length, 3);
      expect(entry.stale, isFalse, reason: 'just written, should be fresh');
      final restored = entry.items.first;
      expect(restored.title, original.first.title);
      expect(restored.url, original.first.url);
      expect(restored.author, original.first.author);
      expect(restored.cover, original.first.cover);
      expect(restored.latestChapter, original.first.latestChapter);
      expect(restored.rating, original.first.rating);
      expect(restored.coverHeaders, original.first.coverHeaders);
    });

    test('a miss returns null rather than throwing', () async {
      final entry = await cache().read(
        providerId: 'nope',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
      );
      expect(entry, isNull);
    });

    test('an empty page caches as an empty list, not a miss', () async {
      final c = cache();
      await c.write(
        providerId: 'empty-src',
        mode: 'latest',
        query: '',
        filters: const FilterValues(),
        page: 1,
        items: const [],
      );
      final entry = await c.read(
        providerId: 'empty-src',
        mode: 'latest',
        query: '',
        filters: const FilterValues(),
        page: 1,
      );
      expect(entry, isNotNull);
      expect(entry!.items, isEmpty);
    });
  });

  group('key isolation', () {
    test('page number separates pages', () async {
      final c = cache();
      await c.write(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
        items: items(2, prefix: 'page1'),
      );
      await c.write(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 2,
        items: items(2, prefix: 'page2'),
      );

      final p1 = await c.read(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
      );
      final p2 = await c.read(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 2,
      );
      expect(p1!.items.first.title, 'page1 0');
      expect(p2!.items.first.title, 'page2 0');
    });

    test('mode separates popular from latest', () async {
      final c = cache();
      await c.write(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
        items: items(1, prefix: 'popular'),
      );
      await c.write(
        providerId: 'p',
        mode: 'latest',
        query: '',
        filters: const FilterValues(),
        page: 1,
        items: items(1, prefix: 'latest'),
      );

      final popular = await c.read(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
      );
      final latest = await c.read(
        providerId: 'p',
        mode: 'latest',
        query: '',
        filters: const FilterValues(),
        page: 1,
      );
      expect(popular!.items.first.title, 'popular 0');
      expect(latest!.items.first.title, 'latest 0');
    });

    test('provider separates sources', () async {
      final c = cache();
      await c.write(
        providerId: 'a',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
        items: items(1, prefix: 'srcA'),
      );
      final other = await c.read(
        providerId: 'b',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
      );
      expect(other, isNull);
    });

    test('filters separate filtered from unfiltered pages', () async {
      final c = cache();
      await c.write(
        providerId: 'p',
        mode: 'latest',
        query: '',
        filters: const FilterValues(),
        page: 1,
        items: items(1, prefix: 'all'),
      );
      await c.write(
        providerId: 'p',
        mode: 'latest',
        query: '',
        filters: FilterValues({'genre': 'Fantasy'}),
        page: 1,
        items: items(1, prefix: 'fantasy'),
      );

      final unfiltered = await c.read(
        providerId: 'p',
        mode: 'latest',
        query: '',
        filters: const FilterValues(),
        page: 1,
      );
      final filtered = await c.read(
        providerId: 'p',
        mode: 'latest',
        query: '',
        filters: FilterValues({'genre': 'Fantasy'}),
        page: 1,
      );
      expect(unfiltered!.items.first.title, 'all 0');
      expect(filtered!.items.first.title, 'fantasy 0');
    });

    test('search query separates different searches', () async {
      final c = cache();
      await c.write(
        providerId: 'p',
        mode: 'search',
        query: 'martial',
        filters: const FilterValues(),
        page: 1,
        items: items(1, prefix: 'martial'),
      );
      final other = await c.read(
        providerId: 'p',
        mode: 'search',
        query: 'romance',
        filters: const FilterValues(),
        page: 1,
      );
      expect(other, isNull);
    });
  });

  group('freshness', () {
    test('an entry past its window is served but marked stale', () async {
      // freshFor: Duration.zero forces the entry stale immediately, which is
      // what the stale-while-revalidate path keys off.
      await db.browseCacheDao.putPage(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filterHash: filterFingerprint(const FilterValues()),
        page: 1,
        payload: jsonEncode(items(1).map((e) => e.toJson()).toList()),
        itemCount: 1,
        freshFor: Duration.zero,
      );

      final entry = await cache().read(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
      );
      expect(entry, isNotNull);
      expect(entry!.stale, isTrue);
      // Still usable: stale content beats a spinner.
      expect(entry.items.length, 1);
    });

    test('rewriting an entry refreshes it', () async {
      final c = cache();
      await c.write(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
        items: items(1, prefix: 'first'),
      );
      await c.write(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
        items: items(1, prefix: 'second'),
      );

      final entry = await c.read(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
      );
      expect(entry!.items.first.title, 'second 0');
      expect(entry.stale, isFalse);
      // Upsert, not accumulate: one key, one row.
      expect(await c.entryCount(), 1);
    });
  });

  group('invalidation', () {
    test('clearProvider drops only that source', () async {
      final c = cache();
      for (final id in ['a', 'b']) {
        await c.write(
          providerId: id,
          mode: 'popular',
          query: '',
          filters: const FilterValues(),
          page: 1,
          items: items(1),
        );
      }
      expect(await c.entryCount(), 2);

      await c.invalidateProvider('a');
      expect(await c.entryCount(), 1);
      expect(
        await c.read(
          providerId: 'a',
          mode: 'popular',
          query: '',
          filters: const FilterValues(),
          page: 1,
        ),
        isNull,
      );
      expect(
        await c.read(
          providerId: 'b',
          mode: 'popular',
          query: '',
          filters: const FilterValues(),
          page: 1,
        ),
        isNotNull,
      );
    });

    test('clear drops everything', () async {
      final c = cache();
      for (final id in ['a', 'b']) {
        await c.write(
          providerId: id,
          mode: 'popular',
          query: '',
          filters: const FilterValues(),
          page: 1,
          items: items(1),
        );
      }
      await c.clear();
      expect(await c.entryCount(), 0);
    });

    test('sizeBytes reflects stored payloads', () async {
      final c = cache();
      await c.write(
        providerId: 'p',
        mode: 'popular',
        query: '',
        filters: const FilterValues(),
        page: 1,
        items: items(5),
      );
      expect(await c.sizeBytes(), greaterThan(0));
      await c.clear();
      expect(await c.sizeBytes(), 0);
    });

    test('prune drops entries past maxAge', () async {
      final stamp =
          DateTime.now().millisecondsSinceEpoch -
          BrowseCacheDao.maxAge.inMilliseconds -
          Duration.millisecondsPerSecond;
      await db
          .into(db.browseCache)
          .insert(
            BrowseCacheCompanion.insert(
              cacheKey: 'old|popular||0|1',
              providerId: 'old',
              mode: 'popular',
              payload: '[]',
              fetchedAt: stamp,
              staleAfter: stamp,
            ),
          );
      // A current entry must survive the same prune.
      await writeFreshEntry(db);

      expect(await db.browseCacheDao.count(), 2);
      final removed = await db.browseCacheDao.prune();
      expect(removed, 1);
      expect(await db.browseCacheDao.count(), 1);
    });
  });

  test('a corrupt payload degrades to a miss, not a crash', () async {
    await db.browseCacheDao.putPage(
      providerId: 'p',
      mode: 'popular',
      query: '',
      filterHash: filterFingerprint(const FilterValues()),
      page: 1,
      payload: 'not json at all {{{',
      itemCount: 0,
    );

    final entry = await cache().read(
      providerId: 'p',
      mode: 'popular',
      query: '',
      filters: const FilterValues(),
      page: 1,
    );
    expect(entry, isNull);
  });
}
