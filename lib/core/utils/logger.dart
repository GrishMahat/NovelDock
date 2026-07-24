import 'package:flutter/foundation.dart';

/// Simple structured logger for QuickNovel.
/// In release mode, only warnings and errors are logged.
class Log {
  static const String _reset = '\x1B[0m';
  static const String _red = '\x1B[31m';
  static const String _yellow = '\x1B[33m';
  static const String _green = '\x1B[32m';
  static const String _cyan = '\x1B[36m';
  static const String _gray = '\x1B[90m';

  static void d(String tag, String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('$_gray[$tag] $message$_reset');
    }
  }

  static void i(String tag, String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('$_cyan[$tag] $message$_reset');
    }
  }

  static void w(String tag, String message) {
    // ignore: avoid_print
    print('$_yellow[$tag] WARN: $message$_reset');
  }

  static void e(String tag, String message, [Object? error]) {
    // ignore: avoid_print
    print('$_red[$tag] ERROR: $message$_reset');
    if (error != null) {
      // ignore: avoid_print
      print('$_red[$tag]   $error$_reset');
    }
  }

  static void ok(String tag, String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('$_green[$tag] OK: $message$_reset');
    }
  }
}
