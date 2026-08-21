import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';

import '../../core/utils/logger.dart';

const _tag = 'BGService';

/// Background download service — keeps downloads running when app is backgrounded.
/// Uses flutter_background_service for Android foreground service.
/// No-op on desktop platforms (Linux, macOS, Windows).
class BackgroundDownloadService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();
  static bool _initialized = false;

  /// Initialize and start the background service.
  static Future<void> init() async {
    if (_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: false,
          isForegroundMode: true,
          foregroundServiceNotificationId: 8888,
          initialNotificationTitle: 'NovelDock',
          initialNotificationContent: 'Download service ready',
          foregroundServiceTypes: [AndroidForegroundType.dataSync],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onStart,
          onBackground: _onIosBackground,
        ),
      );

      _initialized = true;
      Log.ok(_tag, 'Background service configured');
    } catch (e) {
      Log.e(_tag, 'Failed to configure background service', e);
    }
  }

  /// Start the background service for downloads.
  static Future<void> start() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (!_initialized) await init();
    try {
      await _service.startService();
      Log.i(_tag, 'Background service started');
    } catch (e) {
      Log.e(_tag, 'Failed to start background service', e);
    }
  }

  /// Stop the background service.
  static Future<void> stop() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final service = FlutterBackgroundService();
      service.invoke('stop');
      Log.i(_tag, 'Background service stopped');
    } catch (e) {
      Log.e(_tag, 'Failed to stop background service', e);
    }
  }

  /// Update the notification content.
  static Future<void> updateNotification({
    required String title,
    required String content,
  }) async {
    try {
      _service.invoke('updateNotification', {
        'title': title,
        'content': content,
      });
    } catch (_) {}
  }

  static bool get isRunning => _initialized;
}

/// Background isolate entry point.
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Handle stop command
  service.on('stop').listen((_) {
    service.stopSelf();
  });

  // Handle notification update
  service.on('updateNotification').listen((event) {
    if (event != null && service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: event['title'] ?? 'NovelDock',
        content: event['content'] ?? 'Downloading...',
      );
    }
  });

  // Keep the service alive
  service.on('setAsForeground').listen((_) {
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }
  });

  service.on('setAsBackground').listen((_) {
    if (service is AndroidServiceInstance) {
      service.setAsBackgroundService();
    }
  });

  Log.ok(_tag, 'Background service isolate started');
}

/// iOS background handler.
@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  return true;
}
