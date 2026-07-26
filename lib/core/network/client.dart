import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
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

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent': 'NovelBase/1.0',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.5',
    },
  ));

  dio.interceptors.add(CookieManager(cookieJar));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      Log.d(_tag, 'HTTP ${options.method} ${options.uri}');
      handler.next(options);
    },
    onResponse: (response, handler) {
      Log.d(_tag, 'HTTP ${response.statusCode} ${response.requestOptions.uri}');
      handler.next(response);
    },
    onError: (error, handler) async {
      Log.w(_tag, 'HTTP error: ${error.type} ${error.requestOptions.uri}');

      // Check for Cloudflare challenge
      if (error.response != null && CloudflareHandler.isCloudflareChallenge(error.response!)) {
        Log.w(_tag, 'Cloudflare challenge detected for: ${error.requestOptions.uri}');
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
  ));

  Log.ok(_tag, 'Dio HTTP client ready');
  return dio;
});

bool _shouldRetry(DioException error) {
  return error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.connectionError;
}

extension CloudflareCheck on Response {
  bool get isCloudflareChallenge {
    return CloudflareHandler.isCloudflareChallenge(this);
  }
}

/// Provider for Cloudflare bypass handler
final cloudflareProvider = Provider<CloudflareHandler>((ref) {
  return CloudflareHandler();
});
