import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/logger.dart';
import 'tts_engine.dart';

const _tag = 'SystemTts';

/// ISO 639-2/3 → 639-1 mappings for languages Android TTS engines commonly
/// report (Android `Locale.toLanguageTag()` yields tags like `eng-USA`).
const Map<String, String> _iso639ToBcp47 = {
  'afr': 'af',
  'amh': 'am',
  'ara': 'ar',
  'ben': 'bn',
  'bul': 'bg',
  'cat': 'ca',
  'ces': 'cs',
  'cze': 'cs',
  'dan': 'da',
  'deu': 'de',
  'ell': 'el',
  'eng': 'en',
  'spa': 'es',
  'est': 'et',
  'fas': 'fa',
  'fin': 'fi',
  'fil': 'fil',
  'fra': 'fr',
  'fre': 'fr',
  'guj': 'gu',
  'heb': 'he',
  'hin': 'hi',
  'hrv': 'hr',
  'hun': 'hu',
  'ind': 'id',
  'isl': 'is',
  'ita': 'it',
  'jpn': 'ja',
  'kan': 'kn',
  'kor': 'ko',
  'lit': 'lt',
  'lav': 'lv',
  'mkd': 'mk',
  'mlt': 'mt',
  'mar': 'mr',
  'msa': 'ms',
  'mya': 'my',
  'nld': 'nl',
  'nor': 'no',
  'pol': 'pl',
  'por': 'pt',
  'ron': 'ro',
  'rus': 'ru',
  'sin': 'si',
  'slk': 'sk',
  'slv': 'sl',
  'srp': 'sr',
  'swe': 'sv',
  'tam': 'ta',
  'tel': 'te',
  'tha': 'th',
  'tur': 'tr',
  'ukr': 'uk',
  'urd': 'ur',
  'vie': 'vi',
  'zho': 'zh',
  'chi': 'zh',
};

/// ISO 3166-1 alpha-3 → alpha-2 region mappings (Android emits `eng-USA`).
const Map<String, String> _iso3166ToAlpha2 = {
  'ARG': 'AR',
  'AUS': 'AU',
  'AUT': 'AT',
  'BEL': 'BE',
  'BGR': 'BG',
  'BRA': 'BR',
  'CAN': 'CA',
  'CHE': 'CH',
  'CHL': 'CL',
  'CHN': 'CN',
  'COL': 'CO',
  'CRI': 'CR',
  'CZE': 'CZ',
  'DEU': 'DE',
  'DNK': 'DK',
  'EGY': 'EG',
  'ESP': 'ES',
  'FIN': 'FI',
  'FRA': 'FR',
  'GBR': 'GB',
  'GRC': 'GR',
  'HKG': 'HK',
  'HRV': 'HR',
  'HUN': 'HU',
  'IDN': 'ID',
  'IND': 'IN',
  'IRL': 'IE',
  'IRN': 'IR',
  'IRQ': 'IQ',
  'ISR': 'IL',
  'ITA': 'IT',
  'JPN': 'JP',
  'KOR': 'KR',
  'LTU': 'LT',
  'LVA': 'LV',
  'MEX': 'MX',
  'MKD': 'MK',
  'MLT': 'MT',
  'MYS': 'MY',
  'NGA': 'NG',
  'NLD': 'NL',
  'NOR': 'NO',
  'NZL': 'NZ',
  'PAK': 'PK',
  'PER': 'PE',
  'PHL': 'PH',
  'POL': 'PL',
  'PRT': 'PT',
  'ROU': 'RO',
  'RUS': 'RU',
  'SAU': 'SA',
  'SGP': 'SG',
  'SRB': 'RS',
  'SVK': 'SK',
  'SVN': 'SI',
  'SWE': 'SE',
  'THA': 'TH',
  'TUN': 'TN',
  'TUR': 'TR',
  'TWN': 'TW',
  'UKR': 'UA',
  'URY': 'UY',
  'USA': 'US',
  'VEN': 'VE',
  'VNM': 'VN',
  'ZAF': 'ZA',
};

/// Converts an Android TTS locale tag (`eng-USA`, `rus-RUS`) into the BCP-47
/// style used across the app (`en-US`). Unknown language/region codes pass
/// through with normalized casing.
String normalizeAndroidTtsLocale(String tag) {
  final trimmed = tag.trim();

  if (trimmed.isEmpty) return trimmed;

  final parts = trimmed.split('-');

  var language = parts.first.toLowerCase();

  if (language.length == 3) {
    language = _iso639ToBcp47[language] ?? language;
  }

  parts[0] = language;

  for (var i = 1; i < parts.length; i++) {
    final upper = parts[i].toUpperCase();

    // Region subtag; Android engines emit alpha-3 codes such as USA.
    if (upper.length == 3) {
      parts[i] = _iso3166ToAlpha2[upper] ?? upper;
    } else if (parts[i].length == 4) {
      // Script subtag.
      parts[i] =
          parts[i].substring(0, 1).toUpperCase() +
          parts[i].substring(1).toLowerCase();
    } else {
      parts[i] = upper;
    }
  }

  return parts.join('-');
}

/// On-device platform TTS engine (Android system TextToSpeech).
///
/// The platform engine cannot stream audio bytes while speaking, so this
/// implementation synthesizes each turn to a temporary WAV file
/// ([FlutterTts.synthesizeToFile] with a full path) and emits the bytes as
/// one [TtsAudioBytes] event. Word boundaries are unavailable.
class SystemTtsEngine extends TtsEngine {
  /// Whether the underlying platform plugin can run here.
  static bool get isSupported => Platform.isAndroid;

  FlutterTts? _tts;

  /// Voice id → original Android locale tag (`eng-USA`-style). The plugin's
  /// setVoice() requires an exact match against
  /// `voice.locale.toLanguageTag()`, so the raw tag must be preserved for
  /// selection while the normalized form is shown in the UI.
  final Map<String, String> _voiceRawLocales = {};

  /// Whether at least one discovery pass has been made.
  bool _voiceDiscoveryAttempted = false;

  @override
  String get id => 'system';

  @override
  String get displayName => 'Device voice';

  @override
  bool get supportsWordBoundaries => false;

  @override
  bool get requiresNetwork => false;

  Future<FlutterTts> _ensure() async {
    if (_tts != null) return _tts!;
    final tts = FlutterTts();
    // Makes synthesizeToFile() resolve only after the file is fully written.
    await tts.awaitSynthCompletion(true);
    _tts = tts;
    return tts;
  }

  @override
  Future<void> init() async {
    if (!isSupported) {
      throw UnsupportedError('System TTS is not supported on this platform');
    }
    await _ensure();
  }

  @override
  Future<List<TtsEngineVoice>> getVoices() async {
    if (!isSupported) return const [];
    try {
      final tts = await _ensure();
      final raw = await tts.getVoices;
      if (raw is! List) return const [];

      _voiceRawLocales.clear();
      _voiceDiscoveryAttempted = true;

      final voices = <TtsEngineVoice>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final name = entry['name']?.toString() ?? '';
        final rawLocale = entry['locale']?.toString() ?? '';
        if (name.isEmpty || rawLocale.isEmpty) continue;
        voices.add(
          TtsEngineVoice(
            id: name,
            name: name,
            locale: normalizeAndroidTtsLocale(rawLocale),
          ),
        );
        _voiceRawLocales[name] = rawLocale;
      }
      Log.i(_tag, 'Discovered ${voices.length} system voices');
      return voices;
    } catch (e) {
      Log.e(_tag, 'getVoices failed: $e');
      return const [];
    }
  }

  /// Returns the original Android locale tag for [voiceId], triggering voice
  /// discovery once if needed. Returns null for unknown ids, which callers
  /// treat as "not a system voice" (e.g. an Edge default voice id leaking
  /// into the system engine).
  Future<String?> _rawLocaleFor(String voiceId) async {
    if (voiceId.isEmpty) return null;

    final cached = _voiceRawLocales[voiceId];

    if (cached != null) return cached;

    if (!_voiceDiscoveryAttempted) {
      await getVoices();
    }

    return _voiceRawLocales[voiceId];
  }

  @override
  Future<void> close() async {
    final tts = _tts;
    _tts = null;
    if (tts == null) return;
    try {
      await tts.stop();
      await tts.setEngine('');
    } catch (_) {}
  }

  @override
  void reopen() {}

  /// Maps an Edge-style rate string (`+10%`) to a speech-rate multiplier
  /// where 1.0 is the platform default.
  double _rateFrom(String rate) {
    final match = RegExp(r'([+-]?\d+(?:\.\d+)?)\s*%').firstMatch(rate);
    final pct = match == null ? 0.0 : double.parse(match.group(1)!);
    return (1.0 + pct / 100).clamp(0.25, 4.0);
  }

  /// Maps an Edge-style pitch string (`+10Hz`, or a `%` value from legacy
  /// callers) to the platform pitch scale (0.5 to 2.0, default 1.0).
  double _pitchFrom(String pitch) {
    final hzMatch = RegExp(r'([+-]?\d+(?:\.\d+)?)\s*Hz').firstMatch(pitch);
    if (hzMatch != null) {
      return (1.0 + double.parse(hzMatch.group(1)!) / 200).clamp(0.5, 2.0);
    }
    final pctMatch = RegExp(r'([+-]?\d+(?:\.\d+)?)\s*%').firstMatch(pitch);
    final pct = pctMatch == null ? 0.0 : double.parse(pctMatch.group(1)!);
    return (1.0 + pct / 100).clamp(0.5, 2.0);
  }

  @override
  Stream<TtsSynthesisEvent> synthesize(
    String text, {
    required String voiceId,
    required String rate,
    required String pitch,
    String? locale,
  }) async* {
    try {
      final tts = await _ensure();

      // The plugin's setVoice() only succeeds when both the name and the
      // exact Android locale tag (`eng-USA`-style) match a discovered voice,
      // so the resolved raw tag — not the app-level `en-US` language — is
      // passed here. Unknown ids (e.g. an Edge default voice) are skipped and
      // fall through to setLanguage().
      var voiceSet = false;
      final rawLocale = await _rawLocaleFor(voiceId);
      if (rawLocale != null) {
        voiceSet =
            await tts.setVoice({'name': voiceId, 'locale': rawLocale}) == 1;

        if (!voiceSet) {
          Log.w(_tag, 'setVoice rejected $voiceId ($rawLocale)');
        }
      }
      if (!voiceSet && locale != null && locale.isNotEmpty) {
        await tts.setLanguage(locale);
      }
      await tts.setSpeechRate(_rateFrom(rate));
      await tts.setPitch(_pitchFrom(pitch));

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/noveldock_tts_${DateTime.now().microsecondsSinceEpoch}.wav',
      );

      final result = await tts.synthesizeToFile(text, file.path, true);
      if (result != 1) {
        throw Exception('System TTS rejected synthesis (code: $result)');
      }

      final bytes = await file.readAsBytes();
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}

      if (bytes.isEmpty) {
        throw Exception('System TTS produced an empty audio file');
      }

      yield TtsAudioBytes(bytes);
      yield const TtsTurnEnd();
    } catch (e) {
      yield TtsSynthesisError(e);
    }
  }
}
