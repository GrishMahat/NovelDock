// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'log_buffer.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod provider that bridges the global log buffer.
/// Listener-backed: emits only when entries are added (no polling), and
/// auto-disposes with the log page. New listeners immediately get the
/// current buffer so reopening the page never flashes empty.

@ProviderFor(logBuffer)
final logBufferProvider = LogBufferProvider._();

/// Riverpod provider that bridges the global log buffer.
/// Listener-backed: emits only when entries are added (no polling), and
/// auto-disposes with the log page. New listeners immediately get the
/// current buffer so reopening the page never flashes empty.

final class LogBufferProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LogEntry>>,
          List<LogEntry>,
          Stream<List<LogEntry>>
        >
    with $FutureModifier<List<LogEntry>>, $StreamProvider<List<LogEntry>> {
  /// Riverpod provider that bridges the global log buffer.
  /// Listener-backed: emits only when entries are added (no polling), and
  /// auto-disposes with the log page. New listeners immediately get the
  /// current buffer so reopening the page never flashes empty.
  LogBufferProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'logBufferProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$logBufferHash();

  @$internal
  @override
  $StreamProviderElement<List<LogEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<LogEntry>> create(Ref ref) {
    return logBuffer(ref);
  }
}

String _$logBufferHash() => r'03f017fbaf3c7719d387ad130ee48ce98eb298b1';
