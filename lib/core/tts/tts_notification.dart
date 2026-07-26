import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/logger.dart';

const _tag = 'TTSNotif';

class TtsNotification {
  static const _channelId = 'tts_playback';
  static const _channelName = 'TTS Playback';
  static const _notifId = 9999;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _showing = false;
  static String? _coverPath;

  static Function()? onPause;
  static Function()? onResume;
  static Function()? onStop;
  static Function()? onSkipForward;
  static Function()? onSkipBackward;

  static Future<void> init() async {
    if (_initialized) return;
    if (Platform.isLinux) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onAction,
    );
    _initialized = true;
    Log.ok(_tag, 'Notification initialized');
  }

  static void _onAction(NotificationResponse response) {
    switch (response.actionId) {
      case 'pause': onPause?.call(); break;
      case 'resume': onResume?.call(); break;
      case 'stop': onStop?.call(); break;
      case 'skip_forward': onSkipForward?.call(); break;
      case 'skip_backward': onSkipBackward?.call(); break;
    }
  }

  /// Download cover image for notification large icon.
  static Future<void> setCoverArt(String? coverUrl) async {
    if (coverUrl == null || coverUrl.isEmpty) {
      _coverPath = null;
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = p.join(tempDir.path, 'tts_notif_cover.jpg');
      final file = File(filePath);

      // Always try to download if file doesn't exist or is empty/corrupt
      final exists = await file.exists();
      final hasContent = exists && await file.length() > 100;
      if (!hasContent) {
        final response = await http.get(Uri.parse(coverUrl)).timeout(
          const Duration(seconds: 10),
          onTimeout: () => http.Response('', 408),
        );
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          await file.writeAsBytes(response.bodyBytes);
          Log.ok(_tag, 'Cover downloaded: ${response.bodyBytes.length} bytes');
        } else {
          Log.w(_tag, 'Cover download failed: ${response.statusCode}');
          _coverPath = null;
          return;
        }
      }
      _coverPath = filePath;
    } catch (e) {
      Log.e(_tag, 'Failed to download cover for notification', e);
      _coverPath = null;
    }
  }

  static Future<void> show({
    required String chapterName,
    required int currentLine,
    required int totalLines,
    required bool isPaused,
    String? novelTitle,
  }) async {
    if (!_initialized || Platform.isLinux) return;

    final title = novelTitle ?? 'NovelBase';
    final status = isPaused ? 'Paused' : 'Playing';

    AndroidNotificationDetails androidDetails;

    final hasCover = _coverPath != null && await File(_coverPath!).exists();

    if (hasCover) {
      androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'TTS playback controls',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        showWhen: false,
        largeIcon: FilePathAndroidBitmap(_coverPath!),
        styleInformation: BigPictureStyleInformation(
          FilePathAndroidBitmap(_coverPath!),
          contentTitle: title,
          summaryText: '$status · Line $currentLine of $totalLines',
        ),
        actions: [
          if (isPaused)
            const AndroidNotificationAction('resume', 'Play', showsUserInterface: false)
          else
            const AndroidNotificationAction('pause', 'Pause', showsUserInterface: false),
          const AndroidNotificationAction('skip_forward', 'Next', showsUserInterface: false),
          const AndroidNotificationAction('stop', 'Stop', showsUserInterface: false),
        ],
      );
    } else {
      androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'TTS playback controls',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        showWhen: false,
        styleInformation: BigTextStyleInformation(
          '$title\n$chapterName',
          contentTitle: title,
          summaryText: '$status · Line $currentLine of $totalLines',
        ),
        actions: [
          if (isPaused)
            const AndroidNotificationAction('resume', 'Play', showsUserInterface: false)
          else
            const AndroidNotificationAction('pause', 'Pause', showsUserInterface: false),
          const AndroidNotificationAction('skip_forward', 'Next', showsUserInterface: false),
          const AndroidNotificationAction('stop', 'Stop', showsUserInterface: false),
        ],
      );
    }

    await _plugin.show(
      id: _notifId,
      title: title,
      body: '$status · $chapterName',
      notificationDetails: NotificationDetails(android: androidDetails),
    );
    _showing = true;
  }

  static Future<void> hide() async {
    if (!_initialized || !_showing) return;
    await _plugin.cancel(id: _notifId);
    _showing = false;
  }
}
