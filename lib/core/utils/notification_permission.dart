import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'logger.dart';

const _tag = 'NotifPerm';

/// Requests the Android 13+ `POST_NOTIFICATIONS` runtime permission.
///
/// Called lazily from the first TTS or download action instead of at every
/// cold start, so the permission dialog appears in context rather than
/// interrupting launch. No-op on non-Android platforms (and on Android the
/// platform implementation itself is a no-op once already granted).
Future<void> ensureNotificationPermission(
  FlutterLocalNotificationsPlugin plugin,
) async {
  if (!Platform.isAndroid) return;

  try {
    final androidPlugin = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final granted = await androidPlugin?.requestNotificationsPermission();
    Log.i(_tag, 'Permission request done (granted: $granted)');
  } catch (e) {
    Log.w(_tag, 'Notification permission request failed: $e');
  }
}
