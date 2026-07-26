import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'logger.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  String get formatted {
    final t = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    final l = level.name.toUpperCase().padRight(7);
    return '$t [$tag] $l $message';
  }
}

/// Global log buffer singleton.
/// Used directly by Log static methods, and bridged to Riverpod via logBufferProvider.
class LogBuffer {
  static const int _maxEntries = 1000;
  final List<LogEntry> _entries = [];
  final List<VoidCallback> _listeners = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(LogLevel level, String tag, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    );
    if (_entries.length >= _maxEntries) {
      _entries.removeAt(0);
    }
    _entries.add(entry);
    for (final l in _listeners) {
      l();
    }
  }

  void clear() {
    _entries.clear();
    for (final l in _listeners) {
      l();
    }
  }

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
}

final globalLogBuffer = LogBuffer();

/// Riverpod provider that bridges the global log buffer.
final logBufferProvider = StreamProvider<List<LogEntry>>((ref) {
  ref.onDispose(() {});
  return Stream<List<LogEntry>>.periodic(
    const Duration(milliseconds: 200),
    (_) => globalLogBuffer.entries,
  ).distinct();
});

/// Initialize log buffer — wires Log.onLog to the global buffer.
void initLogBuffer() {
  Log.onLog = (level, tag, message) {
    globalLogBuffer.add(level, tag, message);
  };
}
