import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
