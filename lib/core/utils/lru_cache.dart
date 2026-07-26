import 'dart:collection';

class LruCache<K, V> with MapMixin<K, V> {
  final int maxSize;
  final _map = <K, V>{};
  final _order = <K>[];

  LruCache(this.maxSize);

  @override
  V? operator [](Object? key) {
    if (key is K && _map.containsKey(key)) {
      _order.remove(key);
      _order.add(key);
      return _map[key];
    }
    return null;
  }

  @override
  void operator []=(K key, V value) {
    if (_map.containsKey(key)) {
      _order.remove(key);
    } else if (_map.length >= maxSize) {
      final oldest = _order.removeAt(0);
      _map.remove(oldest);
    }
    _map[key] = value;
    _order.add(key);
  }

  @override
  V? remove(Object? key) {
    if (key is K && _map.containsKey(key)) {
      _order.remove(key);
      return _map.remove(key);
    }
    return null;
  }

  @override
  void clear() {
    _map.clear();
    _order.clear();
  }

  @override
  Iterable<K> get keys => _map.keys;
}
