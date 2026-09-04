import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../utils/logger.dart';
import 'cloudflare.dart';

const _tag = 'Network';

final cookieJarProvider = FutureProvider<CookieJar>((ref) async {
  final config = await AppConfig.getInstance();
  Log.i(_tag, 'Cookie jar path: ${config.cookiesDir.path}');
  return PersistCookieJar(
    ignoreExpires: true,
    storage: FileStorage(config.cookiesDir.path),
  );
});

final dioProvider = FutureProvider<Dio>((ref) async {
  final cookieJar = await ref.watch(cookieJarProvider.future);
  Log.i(_tag, 'Initializing Dio HTTP client');

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        // Don't use a Chrome user agent. Why? Because it gets flagged.
        // Why, you might ask? I don't know why, but it gets you flagged by
        // Cloudflare. Firefox doesn't get flagged most of the time, and most
        // requests out there are sent using Chrome, so a Chrome user agent
        // sends up a Cloudflare flag. Do you know how much time I spent
        // debugging this without even realizing the user agent was the
        // thing getting me flagged?

        'User-Agent':
            'Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        // And except for this, I thought the Referer header would either
        // help avoid flags or just get ignored, but no, it gets you flagged
        // by Cloudflare too, sometimes. Caused me a lot of pain and problems.
        // Both the user agent and the Referer, I had to find one by one. The
        // error didn't magically change, so at least I knew I was going in the
        // right direction.
        // 'Referer': 'https://www.google.com/',
      },
    ),
  );

  dio.interceptors.add(CookieManager(cookieJar));

  // Use the HTTP/2 adapter on all platforms. Some sites (e.g. Cloudflare
  // protected ones) flag dart:io's plain HTTP/1.1 connections with a 403
  // "Just a moment..." challenge, while HTTP/2 passes. The adapter falls
  // back to dart:io automatically for servers that only support HTTP/1.1.
  //
  // dio_http2_adapter >=2.9.0 lets us advertise http/1.1 alongside h2 via
  // ConnectionManager(supportedProtocols:) — upstream's default offers h2
  // only. Some servers (e.g. yomou.syosetu.com) reply to an h2-only ALPN
  // offer with an invalid extension, killing the handshake; with both
  // protocols offered they pick http/1.1 and the adapter's built-in
  // fallback (IOHttpClientAdapter) handles the request over plain HTTP/1.1
  //
  // KNOWN UPSTREAM BUG (unfixed as of 2.9.0): the adapter treats HTTP/2
  // https://github.com/cfug/dio/issues/2600
  // https://github.com/cfug/dio/pull/2601
  // informational responses (1xx, e.g. 103 Early Hints sent by
  // wuxiaworld.com) as the final response — it completes the response
  // future on the 103 (dio reports a bogus badResponse with status 103)
  // and then throws "Bad state: Future already completed" when the real
  // response arrives. Patch location if we ever need to vendor or
  // upstream: lib/src/http2_adapter.dart, the HeadersStreamMessage branch
  // of _fetch's incomingMessages listener — skip 1xx statuses instead of
  // calling responseCompleter.complete().
  final http2 = Http2Adapter(
    ConnectionManager(supportedProtocols: const ['h2', 'http/1.1']),
  );
  dio.httpClientAdapter = http2;
  ref.onDispose(() => http2.connectionManager.close());
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        Log.d(_tag, 'HTTP ${options.method} ${options.uri}');
        handler.next(options);
      },
      onResponse: (response, handler) {
        Log.d(
          _tag,
          'HTTP ${response.statusCode} ${response.requestOptions.uri}',
        );
        handler.next(response);
      },
      onError: (error, handler) async {
        Log.w(_tag, 'HTTP error: ${error.type} ${error.requestOptions.uri}');

        // Check for Cloudflare challenge
        if (error.response != null &&
            CloudflareHandler.isCloudflareChallenge(error.response!)) {
          Log.w(
            _tag,
            'Cloudflare challenge detected for: ${error.requestOptions.uri}',
          );
          // Store the error info so callers can trigger WebView bypass
          error.requestOptions.extra['cloudflare'] = true;
        }

        if (_shouldRetry(error)) {
          final retries = error.requestOptions.extra['retries'] ?? 0;
          if (retries < 3) {
            error.requestOptions.extra['retries'] = retries + 1;
            Log.i(_tag, 'Retrying (${retries + 1}/3)...');
            await Future.delayed(Duration(seconds: (retries + 1) * 2));
            try {
              final response = await dio.fetch(error.requestOptions);
              handler.resolve(response);
              return;
            } catch (_) {}
          }
        }
        handler.next(error);
      },
    ),
  );

  Log.ok(_tag, 'Dio HTTP client ready');
  return dio;
});

bool _shouldRetry(DioException error) {
  return error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.connectionError;
}
