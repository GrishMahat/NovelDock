import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noveldock/core/network/errors.dart';

// Pins the user-facing cause mapping: every fetch failure must say WHAT
// happened (offline, timeout, server status) instead of spinning forever
// or printing raw exceptions.
void main() {
  DioException dioError(
    DioExceptionType type, {
    int? statusCode,
    String? message,
  }) {
    return DioException(
      requestOptions: RequestOptions(path: 'https://example.com/'),
      type: type,
      message: message,
      response: statusCode == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: 'https://example.com/'),
              statusCode: statusCode,
            ),
    );
  }

  group('NetworkFailure.from', () {
    test('offline factory message', () {
      final f = NetworkFailure.offline();
      expect(f.message, 'No connection');
      expect(f.details, isNotNull);
    });

    test('passes NetworkFailure through untouched', () {
      const f = NetworkFailure('X', 'Y');
      expect(NetworkFailure.from(f), same(f));
    });

    test('timeouts say timed out', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      ]) {
        final f = NetworkFailure.from(dioError(type));
        expect(f.message, contains('too long'));
      }
      final f = NetworkFailure.from(
        dioError(DioExceptionType.unknown, message: 'timed out after 15s'),
      );
      expect(f.message, contains('too long'));
    });

    test('connection errors say no connection', () {
      final f = NetworkFailure.from(dioError(DioExceptionType.connectionError));
      expect(f.message, 'No connection');
      final socket = NetworkFailure.from(
        const SocketException('Failed host lookup'),
      );
      expect(socket.message, 'No connection');
    });

    test('HTTP statuses map to causes', () {
      expect(
        NetworkFailure.from(
          dioError(DioExceptionType.badResponse, statusCode: 404),
        ).message,
        contains('Gone'),
      );
      expect(
        NetworkFailure.from(
          dioError(DioExceptionType.badResponse, statusCode: 403),
        ).message,
        contains('Blocked'),
      );
      final server = NetworkFailure.from(
        dioError(DioExceptionType.badResponse, statusCode: 500),
      );
      expect(server.message, contains('problems'));
      expect(server.details, contains('500'));
    });

    test('cancellation stays quiet', () {
      final f = NetworkFailure.from(dioError(DioExceptionType.cancel));
      expect(f.message, 'Cancelled');
    });

    test('unknown errors keep a capped detail line, never raw dumps', () {
      final f = NetworkFailure.from(Exception('weird: ${'x' * 500}'));
      expect(f.message, 'Failed to load');
      expect(f.details, isNotNull);
      expect(f.details!.length, lessThanOrEqualTo(150));
    });
  });
}
