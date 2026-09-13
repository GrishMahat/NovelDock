import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/features/search/search_rank.dart';

void main() {
  group('relevanceScore', () {
    test('exact beats prefix beats substring', () {
      expect(
        relevanceScore('dawn', 'dawn'),
        greaterThan(relevanceScore('dawn', 'dawn of worlds')),
      );
      expect(
        relevanceScore('dawn', 'dawn of worlds'),
        greaterThan(relevanceScore('dawn', 'before the dawn')),
      );
    });

    test('typo-tolerant match outranks unrelated', () {
      expect(
        relevanceScore('sword art', 'swrod art online'),
        greaterThan(relevanceScore('sword art', 'cooking mama')),
      );
    });

    test('empty query or title scores zero', () {
      expect(relevanceScore('', 'anything'), 0.0);
      expect(relevanceScore('query', ''), 0.0);
    });
  });

  group('rankByRelevance', () {
    test('orders by relevance, stable on ties', () {
      final items = ['cooking mama', 'before the dawn', 'dawn', 'dawnbreaker'];
      final ranked = rankByRelevance('dawn', items, (s) => s);
      expect(ranked.first, 'dawn');
      expect(ranked, containsAllInOrder(['dawn', 'dawnbreaker']));
      expect(ranked.last, 'cooking mama');
    });

    test('empty query preserves provider order', () {
      final items = ['b', 'a', 'c'];
      expect(rankByRelevance('', items, (s) => s), ['b', 'a', 'c']);
    });

    test('does not mutate the input list', () {
      final items = ['cooking mama', 'dawn'];
      rankByRelevance('dawn', items, (s) => s);
      expect(items, ['cooking mama', 'dawn']);
    });
  });
}
