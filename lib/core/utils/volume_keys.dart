import 'dart:io';

import 'package:flutter/services.dart';

/// Android volume-key scrolling for the reader.
///
/// Android delivers volume keys to the activity — never to Flutter's key
/// channel — so `MainActivity` forwards them over this channel, but only
/// while Dart has claimed scroll mode (`setEnabled(true)`). Everywhere else
/// (and on every other platform) volume keys behave normally.
///
/// Lifecycle belongs to the reader screen: enable + handler on open, disable
/// + clear on close, and re-apply when the `volumeScroll` setting changes.
class VolumeKeys {
  static const _channel = MethodChannel('dev.grish.noveldock/volume_keys');

  static bool get isSupported => Platform.isAndroid;

  static Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('setEnabled', enabled);
    } catch (_) {
      // Old installs / non-Android shells: reading must never crash on this.
    }
  }

  static void setHandler({
    required VoidCallback onUp,
    required VoidCallback onDown,
  }) {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'volumeUp':
          onUp();
        case 'volumeDown':
          onDown();
      }
    });
  }

  static void clearHandler() {
    if (!isSupported) return;
    _channel.setMethodCallHandler(null);
  }
}
