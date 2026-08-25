import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app.dart';
import 'core/utils/log_buffer.dart';
import 'core/tts/background_audio_handler.dart';
import 'core/utils/window_state.dart';
import 'features/downloads/background_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

BackgroundAudioHandler? audioHandler;

/// File path received from Android share intent, if any.
String? sharedFilePath;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // mpv's network-timeout (media_kit default 5s) maps to ffmpeg's rw_timeout and
  // aborts an idle-but-open stream connection, ending TTS playback early while
  // the engine is still synthesizing the next chunk. Disable it. Also disable
  // media_kit's cache-on-disk default: mpv fails to create its file cache for
  // the localhost TTS streams ("lavf: Failed to create file cache").
  JustAudioMediaKit.mpvProperties = const {
    'network-timeout': '0',
    'cache': 'no',
    'cache-on-disk': 'no',
  };

  // Desktop only: window sizing must happen before the first frame.
  // Everything else below runs after the first frame so cold start on
  // Android is not blocked by plugin initialization.
  if (!Platform.isAndroid && !Platform.isIOS) {
    try {
      JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    } catch (e) {
      debugPrint('JustAudioMediaKit init failed: $e');
    }
    await WindowStateManager.init();
  }

  // Initialize log buffer (captures all Log calls in-memory)
  initLogBuffer();

  runApp(const ProviderScope(child: NovelDockApp()));

  // ── Deferred initialization (post first frame) ──
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    } catch (e) {
      debugPrint('JustAudioMediaKit init failed: $e');
    }

    await _initNotifications();

    await BackgroundDownloadService.init();
  });
}

Future<void> _initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');
  const initSettings = InitializationSettings(
    android: androidSettings,
    linux: linuxSettings,
  );
  await flutterLocalNotificationsPlugin.initialize(settings: initSettings);

  if (!Platform.isAndroid) return;

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  // Android 13+ requires a runtime permission request before ANY
  // notification (TTS, downloads) becomes visible.
  await androidPlugin?.requestNotificationsPermission();

  // Channel ids must match what the notification senders use:
  // audio_service posts to dev.grish.noveldock.tts (see initAudioService).
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'downloads',
      'Downloads',
      description: 'Download progress notifications',
      importance: Importance.low,
    ),
  );
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'dev.grish.noveldock.tts',
      'Text-to-Speech',
      description: 'TTS playback notifications',
      importance: Importance.low,
    ),
  );
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'updates',
      'Updates',
      description: 'Registry and provider update notifications',
      importance: Importance.low,
    ),
  );

  await BackgroundDownloadService.init();
}
