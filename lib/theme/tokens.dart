import 'package:flutter/widgets.dart';

/// 4pt spacing scale. The only paddings/gaps that exist in this app.
abstract final class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;
}

/// One radius family: soft.
abstract final class Radii {
  static const Radius sm = Radius.circular(8);
  static const Radius md = Radius.circular(12);
  static const Radius lg = Radius.circular(16);
  static const BorderRadius card = BorderRadius.all(md);
  static const BorderRadius sheet = BorderRadius.vertical(top: Radius.circular(24));
}

/// Motion tokens, M3-aligned. Durations/curves live here.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150); // press feedback, small state
  static const Duration base = Duration(milliseconds: 250); // in-place UI transitions
  static const Duration enter = Duration(milliseconds: 400); // container/sheet enters (decelerate)
  static const Duration exit = Duration(milliseconds: 250); // exits: 50-75% of enter (accelerate)
}

/// Breakpoints for adaptive layout (compact / medium / expanded).
abstract final class Breakpoints {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;
}

/// Desktop layout consts.
abstract final class Desktop {
  /// Max width for centered content on wide screens (DESIGN.md expanded).
  static const double maxContentWidth = 1400;
  /// Width of the desktop navigation rail.
  static const double railWidth = 88;
  /// Width of the reader chapter slider panel.
  static const double readerSidebarWidth = 300;
  /// Hover zone width on the right edge that reveals the chapter panel.
  static const double readerEdgeZoneWidth = 28;
  /// Max reading measure (line length) in the reader, capped for readability.
  static const double readerMaxWidth = 1000;
  /// Minimum window size (window_manager).
  static const double minWindowWidth = 960;
  static const double minWindowHeight = 600;
  /// Default window size on first launch.
  static const double defaultWindowWidth = 1280;
  static const double defaultWindowHeight = 800;
}