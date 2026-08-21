import 'package:flutter/foundation.dart';
import 'log_buffer.dart';

/// Simple structured logger for NovelDock.
/// In release mode, only warnings and errors are logged.
class Log {
  static const String _reset = '\x1B[0m';
  static const String _red = '\x1B[31m';
  static const String _yellow = '\x1B[33m';
  static const String _green = '\x1B[32m';
  static const String _cyan = '\x1B[36m';
  static const String _gray = '\x1B[90m';

  /// Callback invoked for every log entry (used by LogBuffer).
  static void Function(LogLevel level, String tag, String message)? onLog;

  static void d(String tag, String message) {
    if (kDebugMode) {
      print('$_gray[$tag] $message$_reset');
    }
    onLog?.call(LogLevel.debug, tag, message);
  }

  static void i(String tag, String message) {
    if (kDebugMode) {
      print('$_cyan[$tag] $message$_reset');
    }
    onLog?.call(LogLevel.info, tag, message);
  }

  static void w(String tag, String message) {
    debugPrint('$_yellow[$tag] WARN: $message$_reset');
    onLog?.call(LogLevel.warning, tag, message);
  }

  static void e(String tag, String message, [Object? error]) {
    debugPrint('$_red[$tag] ERROR: $message$_reset');
    if (error != null) {
      debugPrint('$_red[$tag]   $error$_reset');
    }
    onLog?.call(
      LogLevel.error,
      tag,
      error is String ? '$message\n  $error' : '$message\n  $error',
    );
  }

  static void ok(String tag, String message) {
    if (kDebugMode) {
      print('$_green[$tag] OK: $message$_reset');
    }
    onLog?.call(LogLevel.info, tag, message);
  }
}
