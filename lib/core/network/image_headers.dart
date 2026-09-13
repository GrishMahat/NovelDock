import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/logger.dart';
import 'client.dart';

const _tag = 'ImageHeaders';

/// Request headers for chapter body images.
///
/// `Image.network` (and `CachedNetworkImage`) don't go through dio, so they
/// miss the scraper cookie jar — images on Cloudflare-protected hosts fail
/// with a challenge page instead of pixels. This replays the jar's cookies
/// for the image host as a plain `Cookie` header.
///
/// Only cookies are sent: no User-Agent spoofing, no Referer (both have been
/// observed to attract Cloudflare challenges rather than deflect them — see
/// the comments in `client.dart`). Empty map on any failure: images then load
/// exactly as before.
Future<Map<String, String>> imageHeadersForUrl(String url, Ref ref) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !uri.host.contains('.')) {
    return const {};
  }
  try {
    final CookieJar jar = await ref.read(cookieJarProvider.future);
    final cookies = await jar.loadForRequest(uri);
    if (cookies.isEmpty) return const {};
    final value = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    return {'Cookie': value};
  } catch (_) {
    Log.w(_tag, 'Could not resolve image headers for $url');
    return const {};
  }
}
