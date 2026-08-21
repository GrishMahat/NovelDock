import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/tokens.dart';

/// Manages desktop window geometry: minimum size, default size, and
/// persist/restore of the last window bounds between launches.
class WindowStateManager with WindowListener {
  static const _boundsKey = 'window_bounds';

  Timer? _saveTimer;

  static Future<void> init() async {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) return;

    await windowManager.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final saved = _readBounds(prefs);

    final options = WindowOptions(
      size: saved?.size ??
          const Size(Desktop.defaultWindowWidth, Desktop.defaultWindowHeight),
      minimumSize:
          const Size(Desktop.minWindowWidth, Desktop.minWindowHeight),
      center: saved == null,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      if (saved != null) {
        await windowManager.setBounds(saved);
      }
      await windowManager.show();
      await windowManager.focus();
    });

    final manager = WindowStateManager();
    windowManager.addListener(manager);
  }

  static Rect? _readBounds(SharedPreferences prefs) {
    final raw = prefs.getString(_boundsKey);
    if (raw == null) return null;
    final parts = raw.split(',');
    if (parts.length != 4) return null;
    final values = parts.map(double.tryParse).toList();
    if (values.any((v) => v == null)) return null;
    return Rect.fromLTWH(values[0]!, values[1]!, values[2]!, values[3]!);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    // Don't overwrite the last normal bounds while maximized.
    if (await windowManager.isMaximized()) return;

    final bounds = await windowManager.getBounds();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _boundsKey,
      '${bounds.left},${bounds.top},${bounds.width},${bounds.height}',
    );
  }

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowResized() => _scheduleSave();
}