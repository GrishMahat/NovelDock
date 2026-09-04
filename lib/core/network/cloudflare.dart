import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';

/// Detects Cloudflare challenge pages and captures clearance cookies.
///
/// Challenge resolution itself happens in the in-app browser
/// ([WebViewScreen]); a challenge is detected there on every loaded page and
/// a verification banner is shown only while one is actually present.
class CloudflareHandler {
  /// Body/header markers that indicate a Cloudflare challenge page.
  static const _challengeMarkers = [
    'cf-browser-verification',
    '__cf_chl_f_tk',
    'cdn-cgi/challenge-platform',
    'Checking your browser',
    'Just a moment',
  ];

  /// Check if a response looks like a Cloudflare challenge.
  static bool isCloudflareChallenge(Response response) {
    final statusCode = response.statusCode ?? 0;
    final body = _bodyAsString(response.data);
    final headers = response.headers;

    // Status codes that indicate Cloudflare
    if (statusCode == 403 || statusCode == 429 || statusCode == 503) {
      if (_looksLikeChallenge(body)) {
        return true;
      }
    }

    // Check for cf-ray header
    if (headers.value('cf-ray') != null) {
      if (statusCode == 403 || statusCode == 503) {
        return true;
      }
    }

    // Check server header
    final server = headers.value('server') ?? '';
    if (server.toLowerCase().contains('cloudflare') &&
        body.contains('challenge')) {
      return true;
    }

    return false;
  }

  /// Check if raw page HTML looks like a Cloudflare challenge.
  static bool looksLikeChallengeHtml(String html) => _looksLikeChallenge(html);

  static bool _looksLikeChallenge(String body) {
    for (final marker in _challengeMarkers) {
      if (body.contains(marker)) return true;
    }
    return false;
  }

  /// Converts Dio response data to a string regardless of responseType.
  /// `.toString()` on raw bytes (e.g. `List<int>`/`Uint8List`) does NOT give
  /// page content — it gives something like "Instance of '_Uint8List'" —
  /// so bytes need to be explicitly utf8-decoded first.
  static String _bodyAsString(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    if (data is List<int>) {
      try {
        return utf8.decode(data, allowMalformed: true);
      } catch (_) {
        return '';
      }
    }
    return data.toString();
  }

  /// Parse a `document.cookie`-style string into name/value pairs.
  static Map<String, String> parseCookieString(String cookieString) {
    final cookies = <String, String>{};
    for (final part in cookieString.split(';')) {
      final trimmed = part.trim();
      final eqIndex = trimmed.indexOf('=');
      if (eqIndex > 0) {
        final name = trimmed.substring(0, eqIndex).trim();
        final value = trimmed.substring(eqIndex + 1).trim();
        cookies[name] = value;
      }
    }
    return cookies;
  }

  /// Store cookies captured from the in-app browser into the app cookie jar
  /// so subsequent Dio requests (provider fetches) carry the clearance.
  static Future<void> persistCookies(
    CookieJar jar,
    Uri uri,
    Map<String, String> cookies,
  ) async {
    if (cookies.isEmpty) return;
    final dioCookies = cookies.entries.map((entry) {
      final cookie = Cookie(entry.key, entry.value)
        ..domain = uri.host
        ..path = '/';
      return cookie;
    }).toList();
    await jar.saveFromResponse(uri, dioCookies);
  }
}
