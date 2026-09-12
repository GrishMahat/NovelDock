import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

/// Human cause of a failed network operation, with a user-facing message
/// plus technical details (the "status" that tells what actually happened).
class NetworkFailure implements Exception {
  final String message;
  final String? details;

  const NetworkFailure(this.message, [this.details]);

  @override
  String toString() => details == null ? message : '$message ($details)';

  /// No connection at all (airplane mode, dead Wi-Fi, no data).
  static NetworkFailure offline() => const NetworkFailure(
    'No connection',
    'Connect to Wi-Fi or mobile data, then retry.',
  );

  /// Maps any fetch error to a cause. Never throws.
  static NetworkFailure from(Object error) {
    if (error is NetworkFailure) return error;
    if (error is DioException) return _fromDio(error);
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Network is unreachable') ||
        text.contains('Connection refused') ||
        text.contains('Connection reset by peer')) {
      return const NetworkFailure(
        'No connection',
        'The server could not be reached. Connect and retry.',
      );
    }
    if (text.contains('TimeoutException') || text.contains('timed out')) {
      return const NetworkFailure(
        'The source is taking too long',
        'It timed out. Retry in a moment.',
      );
    }
    return NetworkFailure('Failed to load', _shortCause(text));
  }

  static NetworkFailure _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const NetworkFailure(
          'The source is taking too long',
          'The request timed out. Retry in a moment.',
        );
      case DioExceptionType.connectionError:
        return const NetworkFailure(
          'No connection',
          'The server could not be reached. Connect and retry.',
        );
      case DioExceptionType.badCertificate:
        return const NetworkFailure(
          'Connection is not secure',
          'The certificate check failed. Do not retry on this network.',
        );
      case DioExceptionType.cancel:
        return const NetworkFailure('Cancelled', null);
      case DioExceptionType.unknown:
        final text = [
          e.message,
          e.error?.toString(),
          e.toString(),
        ].whereType<String>().join(' ');
        if (text.contains('SocketException') ||
            text.contains('Failed host lookup') ||
            text.contains('Network is unreachable')) {
          return const NetworkFailure(
            'No connection',
            'The server could not be reached. Connect and retry.',
          );
        }
        if (text.contains('TimeoutException') || text.contains('timed out')) {
          return const NetworkFailure(
            'The source is taking too long',
            'The request timed out. Retry in a moment.',
          );
        }
        return NetworkFailure('Failed to load', _shortCause(text));
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        if (status == 404) {
          return const NetworkFailure(
            'Gone from the source',
            'The server returned 404 for this page.',
          );
        }
        if (status == 403) {
          return const NetworkFailure(
            'Blocked by the source',
            'The server returned 403. Open it once in Browse so any '
                'verification completes, then retry.',
          );
        }
        if (status != null && status >= 500) {
          return NetworkFailure(
            'The source is having problems',
            'The server returned $status. Retry later.',
          );
        }
        return NetworkFailure(
          'Failed to load',
          status == null ? null : 'The server returned $status.',
        );
    }
  }

  /// First line, capped: details stay readable in a snackbar-sized view.
  static String? _shortCause(String text) {
    final line = text.split('\n').first.trim();
    if (line.isEmpty) return null;
    return line.length > 140 ? '${line.substring(0, 140)}…' : line;
  }
}

/// True when the device reports no usable network. Fast local check used
/// to fail before the 15s connect timeout + retries burn minutes behind a
/// spinner. Fails open (assumes online) when the check itself errors.
Future<bool> isOffline() async {
  try {
    final results = await Connectivity().checkConnectivity();
    if (results.isEmpty) return true;
    return results.every(
      (r) => r == ConnectivityResult.none || r == ConnectivityResult.bluetooth,
    );
  } catch (_) {
    return false;
  }
}
