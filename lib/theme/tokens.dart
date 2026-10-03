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
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(24),
  );
}

/// Motion tokens, M3-aligned. Durations/curves live here.
abstract final class Motion {
  static const Duration fast = Duration(
    milliseconds: 150,
  ); // press feedback, small state
  static const Duration base = Duration(
    milliseconds: 250,
  ); // in-place UI transitions
  static const Duration enter = Duration(
    milliseconds: 400,
  ); // container/sheet enters (decelerate)
  static const Duration exit = Duration(
    milliseconds: 250,
  ); // exits: 50-75% of enter (accelerate)
}

/// Breakpoints for adaptive layout (compact / medium / expanded).
///
/// Values are the *lower bound* of each tier, so a tier holds from its own
/// constant until the next one. `compact` is 0 because every phone width
/// (roughly 320-480dp) belongs there.
abstract final class Breakpoints {
  static const double compact = 0;
  static const double medium = 600;
  static const double expanded = 900;
}

/// Width tiers for adaptive layout.
///
/// Replaces the `isDesktop` boolean for layout decisions. The tiers are
/// width-based rather than platform-based so a narrow desktop window and a
/// large phone resolve to the same layout: both are `compact`.
enum ScreenSize {
  compact,
  medium,
  expanded;

  /// True when the tier is phone-sized or a narrow window.
  bool get isCompact => this == ScreenSize.compact;
}

/// Tier for a width in logical pixels.
///
/// Each [Breakpoints] constant is the *narrowest* width of the next tier up,
/// so a tier holds until the following boundary is reached. Every phone width
/// (roughly 320-480dp) therefore lands in `compact`; a half-screen desktop
/// window lands in `medium`; a maximized window in `expanded`.
ScreenSize screenSizeForWidth(double width) {
  if (width >= Breakpoints.expanded) return ScreenSize.expanded;
  if (width >= Breakpoints.medium) return ScreenSize.medium;
  if (width >= Breakpoints.compact) return ScreenSize.compact;
  return ScreenSize.compact;
}

/// Tier for the nearest [MediaQuery] width. Cheaper than `sizeOf` when only
/// the tier is needed.
ScreenSize screenSizeOf(BuildContext context) =>
    screenSizeForWidth(MediaQuery.sizeOf(context).width);

/// Grid metrics. Column counts are fixed per tier, never derived from a
/// `maxCrossAxisExtent`: extent-derived counts flip between 2 and 3 columns
/// across a 33dp width range, which lands phone users on unusable ~120dp
/// cards. Heights are `mainAxisExtent` rather than `childAspectRatio` so a
/// card's text block never gets squeezed by a changed column count.
abstract final class Grids {
  /// Library covers: 3 across on a phone reads as covers, 2 reads as postage
  /// stamps.
  static int libraryColumns(ScreenSize size) => switch (size) {
    ScreenSize.compact => 3,
    ScreenSize.medium => 4,
    ScreenSize.expanded => 6,
  };

  static double libraryExtent(ScreenSize size) => switch (size) {
    ScreenSize.compact => 205,
    ScreenSize.medium => 215,
    ScreenSize.expanded => 225,
  };

  /// Browse/search results. Wider than a library card because these carry a
  /// title plus a provider line.
  static int browseColumns(ScreenSize size) => switch (size) {
    ScreenSize.compact => 2,
    ScreenSize.medium => 3,
    ScreenSize.expanded => 5,
  };

  static double browseExtent(ScreenSize size) => switch (size) {
    ScreenSize.compact => 260,
    ScreenSize.medium => 270,
    ScreenSize.expanded => 280,
  };

  /// Installed sources: compact 2-up rows rather than one full-width card
  /// per source per screen.
  static int sourceColumns(ScreenSize size) => switch (size) {
    ScreenSize.compact => 2,
    ScreenSize.medium => 2,
    ScreenSize.expanded => 3,
  };

  static double sourceExtent(ScreenSize size) => switch (size) {
    ScreenSize.compact => 56,
    ScreenSize.medium => 64,
    ScreenSize.expanded => 64,
  };
}

/// Bounds for the system text scale.
///
/// The app uses fixed-extent grids and fixed-height reader pills, so an
/// unbounded scale factor overflows them. The upper bound keeps large-text
/// accessibility without breaking layout. Applied via
/// [MediaQuery.withClampedTextScaling] at the app root.
const double kMinTextScale = 1.0;
const double kMaxTextScale = 1.3;

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
