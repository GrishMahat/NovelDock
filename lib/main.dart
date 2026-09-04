import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app.dart';
import 'core/utils/log_buffer.dart';
import 'core/tts/background_audio_handler.dart';

import 'core/utils/window_state.dart';

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
  // Android is not blocked by plugin initialization. media_kit/mpv are
  // playback-only dependencies; loading their native libs here can stall a
  // cold start on desktop with cold OS caches, so that init moved into the
  // post-frame callback below (the earliest TTS play is always later).
  if (!Platform.isAndroid && !Platform.isIOS) {
    await WindowStateManager.init();
  }

  // Initialize log buffer (captures all Log calls in-memory)
  initLogBuffer();

  runApp(const ProviderScope(child: NovelDockApp()));

  // ── Deferred initialization (post first frame) ──
  // Swaps just_audio's platform implementation to the media_kit-backed one on
  // desktop. Without this, just_audio falls back to its method channel, which
  // has no native handler on Linux/Windows, and every TTS playback call throws
  // MissingPluginException. Safe: no AudioPlayer exists before user action.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    try {
      JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    } catch (e) {
      debugPrint('JustAudioMediaKit init failed: $e');
    }
  });
}
