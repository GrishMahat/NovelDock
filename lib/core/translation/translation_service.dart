import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../utils/logger.dart';

const _tag = 'Translation';

/// Translation service using MyMemory API (free, no key required).
/// Includes an in-memory + file-backed cache to avoid re-fetching.
class TranslationService {
  final Map<String, String> _cache = {};
  bool _cacheLoaded = false;

  String _cacheKey(String text, String src, String tgt) {
    // Use base64 of first 100 chars + lang pair as cache key
    final prefix = text.length > 100 ? text.substring(0, 100) : text;
    return base64.encode(utf8.encode('$src|$tgt|$prefix'));
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
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'translation_cache.json'));
      await file.writeAsString(jsonEncode(_cache));
    } catch (e) {
      Log.w(_tag, 'Failed to save translation cache: $e');
    }
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
    final key = _cacheKey(text, sourceLang, targetLang);
    if (_cache.containsKey(key)) {
      Log.d(_tag, 'Cache hit (${text.length} chars)');
      return _cache[key]!;
    }

    // MyMemory API has a ~500 char limit on the q parameter
    const maxChunkSize = 450;
    if (text.length <= maxChunkSize) {
      final result = await _translateChunk(text, sourceLang, targetLang);
      _cache[key] = result;
      _saveCache();
      return result;
    }

    // Split into chunks at sentence boundaries
    final chunks = _splitIntoChunks(text, maxChunkSize);
    final results = <String>[];
    for (final chunk in chunks) {
      results.add(await _translateChunk(chunk, sourceLang, targetLang));
    }
    final combined = results.join(' ');
    _cache[key] = combined;
    _saveCache();
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

  /// Clear the translation cache.
  Future<void> clearCache() async {
    _cache.clear();
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'translation_cache.json'));
      if (await file.exists()) await file.delete();
    } catch (_) {}
    Log.i(_tag, 'Translation cache cleared');
  }

  /// Get cache size.
  int get cacheSize => _cache.length;
}

final translationServiceProvider = Provider<TranslationService>((ref) {
  return TranslationService();
});
