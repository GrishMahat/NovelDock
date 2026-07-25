import 'dart:async';
import 'dart:isolate';

import '../../../core/utils/logger.dart';

const _tag = 'DownloadManager';

/// Lightweight download manager that processes downloads in a background isolate.
/// On Linux, this keeps downloads running while the UI is responsive.
/// On Android, a foreground notification would be needed for true background —
/// for now, downloads continue as long as the app process is alive.
class DownloadManager {
  Isolate? _isolate;
  final Completer<void> _ready = Completer<void>();
  ReceivePort? _receivePort;
  SendPort? _sendPort;

  bool get isRunning => _isolate != null;

  Future<void> start() async {
    if (_isolate != null) return;

    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _downloadIsolateEntry,
      _receivePort!.sendPort,
    );

    // Listen for the SendPort from the isolate
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        if (!_ready.isCompleted) _ready.complete();
      } else if (message is Map) {
        // Progress update from isolate
        final taskId = message['taskId'] as int?;
        final status = message['status'] as String?;
        final progress = message['progress'] as double?;
        Log.d(_tag, 'Task $taskId: $status ($progress)');
      }
    });

    await _ready.future;
    Log.ok(_tag, 'Download manager started');
  }

  Future<void> stop() async {
    _sendPort?.send('stop');
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;
    Log.i(_tag, 'Download manager stopped');
  }

  void dispose() {
    stop();
  }

  static void _downloadIsolateEntry(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message == 'stop') {
        receivePort.close();
        Isolate.exit();
      }
    });
  }
}

/// Singleton download manager
DownloadManager? _instance;
DownloadManager get downloadManager => _instance ??= DownloadManager();
