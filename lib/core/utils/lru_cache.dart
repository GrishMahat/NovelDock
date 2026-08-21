import 'dart:collection';

class LruCache<K, V> with MapMixin<K, V> {
  final int maxSize;
  final _map = <K, V>{};

  LruCache(this.maxSize) : assert(maxSize > 0, 'maxSize must be positive');

  @override
  V? operator [](Object? key) {
    if (key is K && _map.containsKey(key)) {
      final value = _map.remove(key) as V;
      _map[key] = value; // re-insert to mark as most recently used
      return value;
    }
    return null;
  }

  @override
  void operator []=(K key, V value) {
    _map.remove(key); // no-op if absent; ensures reinsert goes to the end
    if (_map.length >= maxSize) {
      _map.remove(_map.keys.first); // evict least recently used
    }
    _map[key] = value;
  }

  @override
  V? remove(Object? key) {
    if (key is K) {
      return _map.remove(key);
    }
    return null;
  }

  @override
  void clear() => _map.clear();

  @override
  Iterable<K> get keys => _map.keys;
}
