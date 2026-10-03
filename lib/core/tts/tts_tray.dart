import 'dart:async';
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
  static TrayIcon? _icon;
  static Image? _iconImage;
  static Menu? _menu;

  /// Native item id -> callback. `MenuItem.id` is get-only, so ids are read
  /// back after creation, and they are only unique within the menu they were
  /// created on — hence rebuilt together with the menu.
  static final Map<int, Future<void> Function()> _actions = {};

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
    } catch (e) {
      Log.w(_tag, 'Tray unavailable: $e');
      _iconPath = null;
    }
  }

  static Future<void> setVisible(bool visible) async {
    if (_iconPath == null) return;
    if (visible == _visible) return;
    _visible = visible;
    try {
      if (!visible) {
        await _destroyIcon();
        return;
      }
      await _createIcon();
    } catch (e) {
      Log.w(_tag, 'Tray update failed: $e');
      // Drop the flag so the next call retries instead of treating a failed
      // create as a successful show.
      if (visible) _visible = false;
    }
  }

  static Future<void> _createIcon() async {
    await _destroyIcon();

    final icon = TrayIcon.create();
    if (icon == null) {
      // Not an exception, so the caller cannot detect it: report failure so
      // setVisible can clear _visible and let a later call retry.
      throw StateError('TrayIcon.create() returned null');
    }
    _icon = icon;

    // Image.fromFile can fail independently of the icon handle; the tray then
    // shows a placeholder but still works.
    _iconImage = Image.fromFile(_iconPath!);
    icon.icon = _iconImage;
    icon.setTooltip('NovelDock — TTS playback');

    await _applyMenu();
  }

  static Future<void> _destroyIcon() async {
    _actions.clear();
    _menu?.dispose();
    _menu = null;
    _icon?.dispose();
    _icon = null;
    _iconImage = null;
  }

  static Future<void> setPaused(bool paused) async {
    _paused = paused;
    if (!_visible) return;
    try {
      await _applyMenu();
    } catch (e) {
      Log.w(_tag, 'Tray menu update failed: $e');
    }
  }

  static Future<void> _applyMenu() async {
    final icon = _icon;
    if (icon == null) return;

    // Rebuilt rather than mutated because the Pause/Resume label tracks
    // playback state. The previous menu must be released first: it is a
    // native handle, and it is dropped from _menu below, so nothing else
    // would ever free it.
    _menu?.dispose();
    _menu = null;
    _actions.clear();

    final menu = Menu.create();
    if (menu == null) {
      throw StateError('Menu.create() returned null');
    }
    _addItem(menu, 'Show NovelDock', _onShow);
    menu.addSeparator();
    _addItem(menu, _paused ? 'Resume' : 'Pause', _onToggle);
    _addItem(menu, 'Stop playback', _onStop);

    menu.addListener((event) {
      if (event is! MenuItemClickedEvent) return;
      // The map is rebuilt with each menu, so a late event from a disposed
      // menu must not resolve against the current one.
      if (!identical(_menu, menu)) return;
      final action = _actions[event.itemId];
      if (action == null) return;
      unawaited(_guardAction(action));
    });

    _menu = menu;
    icon.setContextMenu(menu);
  }

  static void _addItem(
    Menu menu,
    String label,
    Future<void> Function()? action,
  ) {
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
    if (item == null) {
      Log.w(_tag, 'MenuItem.create() returned null for "$label"');
      return;
    }
    if (action != null) _actions[item.id] = action;
    menu.addItem(item);
  }

  static Future<void> _guardAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      Log.w(_tag, 'Tray action failed: $e');
    }
  }

  static Future<void> dispose() async {
    _visible = false;
    try {
      await _destroyIcon();
    } catch (_) {
      // Shutdown path: nothing to do.
    }
  }
}
