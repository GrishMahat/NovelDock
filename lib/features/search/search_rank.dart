/// Relevance ranking for search results (~50 lines, no dependencies).
///
/// Provider rows stay grouped (grouping is how readers compare sources);
/// ranking only reorders items *within* a row by relevance to the query,
/// strongest signal first: exact > prefix > substring > token overlap >
/// typo-tolerant similarity. Stable: ties keep provider order.
double relevanceScore(String query, String title) {
  final q = _normalize(query);
  final t = _normalize(title);
  if (q.isEmpty || t.isEmpty) return 0.0;
  if (t == q) return 1.0;
  if (t.startsWith(q)) return 0.9;
  if (t.contains(q)) return 0.7;

  var best = 0.0;
  final qTokens = q.split(' ').where((s) => s.isNotEmpty).toList();
  if (qTokens.isNotEmpty) {
    final tTokens = t.split(' ').toSet();
    final overlap = qTokens.where(tTokens.contains).length / qTokens.length;
    if (overlap > 0) best = overlap * 0.65;
  }
  final sim = _similarity(q, t);
  if (sim > 0) {
    final weighted = sim * 0.45;
    if (weighted > best) best = weighted;
  }
  return best;
}

/// Returns a relevance-ordered copy; the input list is never mutated.
/// Empty query returns items untouched (provider order).
List<T> rankByRelevance<T>(
  String query,
  List<T> items,
  String Function(T) titleOf,
) {
  if (query.trim().isEmpty) return List<T>.from(items);
  final scored =
      [
        for (var i = 0; i < items.length; i++)
          (index: i, score: relevanceScore(query, titleOf(items[i]))),
      ]..sort((a, b) {
        final cmp = b.score.compareTo(a.score);
        return cmp != 0 ? cmp : a.index.compareTo(b.index);
      });
  return [for (final s in scored) items[s.index]];
}

String _normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Levenshtein similarity in [0, 1], inputs truncated to bound cost.
/// Result lists are small (<100 titles), so O(n*m) with two rows is plenty.
double _similarity(String a, String b) {
  const maxLen = 64;
  var s = a.length > maxLen ? a.substring(0, maxLen) : a;
  var t = b.length > maxLen ? b.substring(0, maxLen) : b;
  if (s.isEmpty || t.isEmpty) return 0.0;
  // Iterate over the shorter string in the inner loop.
  if (s.length > t.length) {
    final tmp = s;
    s = t;
    t = tmp;
  }
  var prev = List<int>.generate(s.length + 1, (i) => i);
  var curr = List<int>.filled(s.length + 1, 0);
  for (var j = 1; j <= t.length; j++) {
    curr[0] = j;
    for (var i = 1; i <= s.length; i++) {
      curr[i] = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1)
          ? prev[i - 1]
          : 1 +
                [
                  prev[i],
                  curr[i - 1],
                  prev[i - 1],
                ].reduce((x, y) => x < y ? x : y);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  final dist = prev[s.length];
  final longest = s.length > t.length ? s.length : t.length;
  return 1.0 - dist / longest;
}
