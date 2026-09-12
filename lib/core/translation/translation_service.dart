import 'dart:convert';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';

part 'translation_service.g.dart';

const _tag = 'Translation';

/// Translation service using MyMemory API (free, no key required).
/// Includes an in-memory + file-backed cache to avoid re-fetching.
class TranslationService {
  final Map<String, String> _cache = {};
  bool _cacheLoaded = false;

  /// Queued saver: concurrent translates chain whole-file writes instead of
  /// racing each other on the cache file.
  Future<void> _saveQueued = Future.value();

  /// Insertion-ordered map doubles as an LRU-ish bound; translation chunks
  /// are small but chapters are many.
  static const int _maxEntries = 2000;

  /// Exact key on the FULL text. A prefix-only key once returned one
  /// chapter's translation for another whenever two texts shared a prefix;
  /// this is the pinned contract (see translation_cache_test).
  static String cacheKey(String text, String src, String tgt) {
    return '$src|$tgt|${text.length}|$text';
  }

  Future<void> _loadCache() async {
    if (_cacheLoaded) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'translation_cache.json'));
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        for (final entry in data.entries) {
          _cache[entry.key] = entry.value as String;
        }
        Log.d(_tag, 'Loaded ${_cache.length} cached translations');
      }
    } catch (e) {
      Log.w(_tag, 'Failed to load translation cache: $e');
    }
    _cacheLoaded = true;
  }

  Future<void> _saveCache() async {
    // Atomic: write temp + rename so a crash mid-write never leaves a
    // truncated cache file behind.
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'translation_cache.json'));
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_cache));
      await tmp.rename(file.path);
    } catch (e) {
      Log.w(_tag, 'Failed to save translation cache: $e');
    }
  }

  /// Enqueues a save behind any in-flight one. Fire-and-forget safe.
  void _saveCacheQueued() {
    _saveQueued = _saveQueued.then((_) => _saveCache());
  }

  void _store(String key, String value) {
    if (!_cache.containsKey(key) && _cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
    _saveCacheQueued();
  }

  /// Translate text from [sourceLang] to [targetLang].
  /// [sourceLang] can be 'auto' for auto-detection.
  Future<String> translate(
    String text, {
    required String sourceLang,
    required String targetLang,
  }) async {
    if (text.trim().isEmpty) return text;
    if (sourceLang == targetLang) return text;

    await _loadCache();

    // Check cache first
    final key = TranslationService.cacheKey(text, sourceLang, targetLang);
    if (_cache.containsKey(key)) {
      Log.d(_tag, 'Cache hit (${text.length} chars)');
      return _cache[key]!;
    }

    // MyMemory API has a ~500 char limit on the q parameter
    const maxChunkSize = 450;
    if (text.length <= maxChunkSize) {
      final result = await _translateChunk(text, sourceLang, targetLang);
      _store(key, result);
      return result;
    }

    // Split into chunks at sentence boundaries
    final chunks = _splitIntoChunks(text, maxChunkSize);
    final results = <String>[];
    for (final chunk in chunks) {
      results.add(await _translateChunk(chunk, sourceLang, targetLang));
    }
    final combined = results.join(' ');
    _store(key, combined);
    return combined;
  }

  List<String> _splitIntoChunks(String text, int maxSize) {
    final chunks = <String>[];
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    var current = '';

    for (final sentence in sentences) {
      if (current.length + sentence.length + 1 > maxSize) {
        if (current.isNotEmpty) chunks.add(current);
        current = sentence;
      } else {
        current = current.isEmpty ? sentence : '$current $sentence';
      }
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  Future<String> _translateChunk(
    String text,
    String sourceLang,
    String targetLang,
  ) async {
    final src = sourceLang == 'auto' ? 'autodetect' : sourceLang;
    final url = Uri.parse(
      'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=$src|$targetLang',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translated = data['responseData']?['translatedText'] as String?;
        if (translated != null && translated.isNotEmpty && translated != text) {
          Log.ok(_tag, 'Translated ${text.length} chars: $src → $targetLang');
          return translated;
        }
      }
      Log.w(_tag, 'Translation returned ${response.statusCode}');
    } catch (e) {
      Log.e(_tag, 'Translation failed', e);
    }

    return text;
  }

  /// Clear the translation cache. Runs behind queued saves so a stale
  /// in-flight write cannot resurrect entries after the clear.
  Future<void> clearCache() {
    _saveQueued = _saveQueued.then((_) async {
      _cache.clear();
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File(p.join(dir.path, 'translation_cache.json'));
        if (await file.exists()) await file.delete();
      } catch (_) {}
      Log.i(_tag, 'Translation cache cleared');
    });
    return _saveQueued;
  }

  /// Get cache size.
  int get cacheSize => _cache.length;
}

@Riverpod(keepAlive: true)
TranslationService translationService(Ref ref) {
  return TranslationService();
}
