import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';

import '../utils/logger.dart';

const _tag = 'TtsTray';

/// Linux system-tray icon for background text-to-speech.
///
/// The icon lives only while TTS is speaking: appear on start, menu flips
/// Pause/Resume with playback state, disappear on stop. Everything degrades
/// silently — a missing indicator daemon, unwritable temp dir, or a
/// headless test shell just means no tray, never a crash.
class TtsTray {
  static bool _ready = false;
  static bool _visible = false;
  static bool _paused = true;
  static String? _iconPath;

  static Future<void> Function()? _onShow;
  static Future<void> Function()? _onToggle;
  static Future<void> Function()? _onStop;

  static Future<void> init({
    required Future<void> Function() onShow,
    required Future<void> Function() onToggle,
    required Future<void> Function() onStop,
  }) async {
    if (!Platform.isLinux) return;
    _onShow = onShow;
    _onToggle = onToggle;
    _onStop = onStop;
    try {
      final bytes = await rootBundle.load('assets/images/logo.png');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/noveldock_tray.png');
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      _iconPath = file.path;
      _ready = true;
    } catch (e) {
      Log.w(_tag, 'Tray unavailable: $e');
    }
  }

  static Future<void> setVisible(bool visible) async {
    if (!_ready || _iconPath == null) return;
    if (visible == _visible) return;
    _visible = visible;
    // Each step is independently guarded: the Linux native side only
    // implements destroy/setIcon/setContextMenu, so one unimplemented
    // method (e.g. setToolTip) must never block the rest.
    if (!visible) {
      await _guard(trayManager.destroy());
      return;
    }
    await _guard(trayManager.setIcon(_iconPath!));
    await _guard(_applyMenu());
  }

  static Future<void> _guard(Future<void> call) async {
    try {
      await call;
    } catch (e) {
      Log.w(_tag, 'Tray update failed: $e');
    }
  }

  static Future<void> setPaused(bool paused) async {
    _paused = paused;
    if (!_ready || !_visible) return;
    try {
      await _applyMenu();
    } catch (e) {
      Log.w(_tag, 'Tray menu update failed: $e');
    }
  }

  static Future<void> _applyMenu() {
    return trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: 'show',
            label: 'Show NovelDock',
            onClick: (_) => _onShow?.call(),
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'toggle',
            label: _paused ? 'Resume' : 'Pause',
            onClick: (_) => _onToggle?.call(),
          ),
          MenuItem(
            key: 'stop',
            label: 'Stop playback',
            onClick: (_) => _onStop?.call(),
          ),
        ],
      ),
    );
  }

  static Future<void> dispose() async {
    _visible = false;
    if (!_ready) return;
    try {
      await trayManager.destroy();
    } catch (_) {
      // Shutdown path: nothing to do.
    }
  }
}
