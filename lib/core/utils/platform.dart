import 'dart:io';

/// True on desktop platforms (Linux, Windows, macOS).
bool get isDesktop =>
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;
