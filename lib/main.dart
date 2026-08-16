import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app.dart';
import 'core/utils/log_buffer.dart';
import 'core/tts/background_audio_handler.dart';
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
  try {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    debugPrint('JustAudioMediaKit initialized successfully');
  } catch (e) {
    debugPrint('JustAudioMediaKit init failed: $e');
    debugPrint('TTS may not work without media_kit native libs');
  }

  // Initialize notification channels
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');
  const initSettings = InitializationSettings(
    android: androidSettings,
    linux: linuxSettings,
  );
  await flutterLocalNotificationsPlugin.initialize(settings: initSettings);

  // Create notification channels (Android only)
  if (Platform.isAndroid) {
    final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
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
        'tts',
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
  }

  // Initialize background download service (Android foreground service)
  BackgroundDownloadService.init();

  // Initialize log buffer (captures all Log calls in-memory)
  initLogBuffer();

  runApp(
    const ProviderScope(
      child: NovelDockApp(),
    ),
  );
}
