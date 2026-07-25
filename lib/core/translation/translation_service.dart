import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../utils/logger.dart';

const _tag = 'Translation';

/// Translation service using MyMemory API (free, no key required).
/// Works on all platforms including Linux.
class TranslationService {
  /// Translate text from [sourceLang] to [targetLang].
  /// [sourceLang] can be 'auto' for auto-detection.
  Future<String> translate(String text, {required String sourceLang, required String targetLang}) async {
    if (text.trim().isEmpty) return text;
    if (sourceLang == targetLang) return text;

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

    return text; // Return original on failure
  }

  /// Translate multiple paragraphs in batch.
  Future<List<String>> translateBatch(List<String> texts, {required String sourceLang, required String targetLang}) async {
    if (texts.isEmpty) return texts;

    // Join with a separator to make fewer API calls
    final separator = '\n\n__SEP__\n\n';
    final combined = texts.join(separator);
    final translated = await translate(combined, sourceLang: sourceLang, targetLang: targetLang);

    // Split back
    final parts = translated.split('__SEP__');
    if (parts.length == texts.length) {
      return parts.map((s) => s.trim()).toList();
    }

    // Fallback: translate individually
    final results = <String>[];
    for (final text in texts) {
      results.add(await translate(text, sourceLang: sourceLang, targetLang: targetLang));
    }
    return results;
  }
}

final translationServiceProvider = Provider<TranslationService>((ref) {
  return TranslationService();
});
