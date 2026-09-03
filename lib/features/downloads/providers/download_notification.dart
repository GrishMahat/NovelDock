import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/utils/logger.dart';

const _tag = 'DownloadNotif';

/// Download notifications.
///
/// Design notes:
/// - One notification per downloading novel ([_notifIdFor]), all sharing a
///   group key, so parallel downloads stack neatly instead of overwriting
///   each other or spawning unrelated entries.
/// - Progress updates replace the existing notification (`onlyAlertOnce`,
///   silent re-post) instead of stacking duplicates.
/// - A Cancel action routes into the download pipeline via [onCancelRequest].
class DownloadNotification {
  static const _channelId = 'downloads';
  static const _channelName = 'Downloads';
  static const _channelDescription = 'Chapter download progress';

  /// Group key shared by every per-novel download notification.
  static const _groupKey = 'dev.grish.noveldock.DOWNLOADS';

  /// Base for per-novel ids; must stay clear of the background service (8888)
  /// and any other fixed slots below this value.
  static const _baseNotifId = 8900;

  /// Action button identifier sent back by the platform.
  static const _cancelActionId = 'noveldock.download.cancel';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Shared plugin instance so permission requests and notification posts
  /// always go through the same platform implementation (and the response
  /// callback stays registered on one instance). Also used by the lazy
  /// notification-permission request (notification_permission.dart).
  static FlutterLocalNotificationsPlugin get plugin => _plugin;

  static bool _initialized = false;
  static Future<void>? _initFuture;

  /// Bridge into the download pipeline; assigned by the provider layer.
  static Future<void> Function(int novelId)? onCancelRequest;

  /// Handles notification taps/actions. Registered once in main.dart's
  /// `_initNotifications` (the single owner of `initialize`) so responses are
  /// never lost to callback re-registration.
  @pragma('vm:entry-point')
  static Future<void> handleNotificationResponse(
    NotificationResponse response,
  ) async {
    try {
      final isAction =
          response.notificationResponseType ==
          NotificationResponseType.selectedNotificationAction;

      // Body taps open the app through the system default intent.
      if (!isAction || response.actionId != _cancelActionId) return;

      final novelId = int.tryParse(response.payload ?? '');
      if (novelId == null) {
        Log.w(_tag, 'Cancel action without a parsable payload');
        return;
      }

      Log.i(_tag, 'Cancellation requested from notification ($novelId)');
      await onCancelRequest?.call(novelId);
    } catch (e) {
      Log.e(_tag, 'Notification response handling failed: $e');
    }
  }

  static Future<void> init() async {
    if (_initialized || Platform.isLinux) return;

    final existing = _initFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final future = _initialize();
    _initFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initFuture, future)) _initFuture = null;
    }
  }

  static Future<void> _initialize() async {
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.low,
          ),
        );
      }

      _initialized = true;
      Log.ok(_tag, 'Download notification initialized');
    } catch (e) {
      Log.e(_tag, 'Failed to initialize download notifications', e);
    }
  }

  static int _notifIdFor(int novelId) => _baseNotifId + novelId;

  static Future<void> showProgress({
    required int novelId,
    required String novelTitle,
    required int completed,
    required int total,
    int failed = 0,
  }) async {
    if (!_initialized || Platform.isLinux) return;

    final progress = total > 0 ? (completed / total * 100).round() : 0;

    final statusParts = <String>[
      '$completed/$total chapters',
      if (failed > 0) '$failed failed',
      if (total > 0) '$progress%',
    ];

    await _plugin.show(
      id: _notifIdFor(novelId),
      title: novelTitle,
      body: statusParts.join(' · '),
      payload: '$novelId',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          groupKey: _groupKey,
          category: AndroidNotificationCategory.progress,
          visibility: NotificationVisibility.public,
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          indeterminate: total == 0,
          maxProgress: 100,
          progress: progress,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          actions: [
            const AndroidNotificationAction(
              _cancelActionId,
              'Cancel',
              showsUserInterface: true,
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> showComplete({
    required int novelId,
    required String novelTitle,
    required int total,
    int failed = 0,
  }) async {
    if (!_initialized || Platform.isLinux) return;

    final body = failed > 0
        ? '$total chapters downloaded · $failed failed'
        : '$total chapter${total == 1 ? '' : 's'} downloaded';

    await _plugin.show(
      id: _notifIdFor(novelId),
      title: 'Download complete: $novelTitle',
      body: body,
      payload: '$novelId',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          groupKey: _groupKey,
          category: AndroidNotificationCategory.status,
          visibility: NotificationVisibility.public,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          ongoing: false,
          autoCancel: true,
        ),
      ),
    );
  }

  static Future<void> hide(int novelId) async {
    if (!_initialized || Platform.isLinux) return;
    try {
      await _plugin.cancel(id: _notifIdFor(novelId));
    } catch (e) {
      Log.w(_tag, 'Failed to hide notification for novel $novelId: $e');
    }
  }
}
