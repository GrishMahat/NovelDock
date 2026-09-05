// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'log_buffer.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Riverpod provider that bridges the global log buffer.

@ProviderFor(logBuffer)
final logBufferProvider = LogBufferProvider._();

/// Riverpod provider that bridges the global log buffer.

final class LogBufferProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LogEntry>>,
          List<LogEntry>,
          Stream<List<LogEntry>>
        >
    with $FutureModifier<List<LogEntry>>, $StreamProvider<List<LogEntry>> {
  /// Riverpod provider that bridges the global log buffer.
  LogBufferProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'logBufferProvider',
        isAutoDispose: false,
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

String _$logBufferHash() => r'329ad5fe5c54c99ed3836c63a335d88eab964642';
