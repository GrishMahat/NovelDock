import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/tts/background_audio_handler.dart';
import 'features/downloads/background_service.dart';

late final BackgroundAudioHandler audioHandler;

/// File path received from Android share intent, if any.
String? sharedFilePath;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  audioHandler = await initAudioService();

  // Initialize background download service (Android foreground service)
  BackgroundDownloadService.init();

  runApp(
    const ProviderScope(
      child: QuickNovelApp(),
    ),
  );
}
