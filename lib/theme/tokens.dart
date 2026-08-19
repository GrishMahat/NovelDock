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
}