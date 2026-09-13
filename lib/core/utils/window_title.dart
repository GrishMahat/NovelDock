import 'dart:io';

import 'package:window_manager/window_manager.dart';

import 'logger.dart';

const _tag = 'WindowTitle';

/// Screen name for a router location, shown as `NovelDock — <screen>` in
/// the desktop title bar. Pure for testing; unknown locations fall back
/// to the bare app name.
String titleFor(String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  if (path == '/' || path.startsWith('/library')) return 'NovelDock — Library';
  if (path.startsWith('/browse')) return 'NovelDock — Browse';
  if (path.startsWith('/history')) return 'NovelDock — History';
  if (path.startsWith('/search')) return 'NovelDock — Search';
  if (path.startsWith('/provider/')) return 'NovelDock — Source';
  if (path.startsWith('/novel/')) return 'NovelDock — Details';
  if (path.startsWith('/reader/')) return 'NovelDock — Reader';
  if (path.startsWith('/downloads')) return 'NovelDock — Downloads';
  if (path.startsWith('/import')) return 'NovelDock — Import';
  if (path == '/settings') return 'NovelDock — Settings';
  if (path.startsWith('/settings/')) return 'NovelDock — Settings';
  return 'NovelDock';
}

/// Applies [titleFor] to the native window. Desktop only; Android/iOS have
/// no window chrome to label. Never throws — a title must never crash boot.
Future<void> applyWindowTitle(String location) async {
  if (Platform.isAndroid || Platform.isIOS) return;
  try {
    await windowManager.setTitle(titleFor(location));
  } catch (e) {
    Log.w(_tag, 'Could not set window title: $e');
  }
}
