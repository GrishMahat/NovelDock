import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/utils/logger.dart';

const _tag = 'DownloadNotif';

/// Download progress notification — same pattern as TtsNotification.
class DownloadNotification {
  static const _channelId = 'downloads';
  static const _channelName = 'Downloads';
  static const _notifId = 8888;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    if (Platform.isLinux) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings: initSettings);
    _initialized = true;
    Log.ok(_tag, 'Download notification initialized');
  }

  static Future<void> showProgress({
    required String novelTitle,
    required int completed,
    required int total,
  }) async {
    if (!_initialized) return;

    final progress = total > 0 ? (completed / total * 100).round() : 0;

    await _plugin.show(
      id: _notifId,
      title: 'Downloading: $novelTitle',
      body: '$completed/$total chapters ($progress%)',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Download progress',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          maxProgress: 100,
          progress: 0,
          onlyAlertOnce: true,
        ),
      ),
    );
  }

  static Future<void> showComplete({
    required String novelTitle,
    required int total,
  }) async {
    if (!_initialized) return;

    await _plugin.show(
      id: _notifId,
      title: 'Download complete',
      body: '$novelTitle: $total chapters downloaded',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Download progress',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  static Future<void> hide() async {
    if (!_initialized) return;
    await _plugin.cancel(id: _notifId);
  }
}
