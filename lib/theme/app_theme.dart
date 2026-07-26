import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';

class AppTheme {
  // Colors from original NovelDock
  static const Color kBackgroundDark = Color(0xFF111111);
  static const Color kBackgroundAmoled = Color(0xFF000000);
  static const Color kBackgroundAmoledLight = Color(0xFF121213);
  static const Color kBackgroundLight = Color(0xFFFFFFFF);
  static const Color kSurfaceVariantDark = Color(0xFF2B2C30);
  static const Color kSurfaceVariantLight = Color(0xFFF1F1F1);
  static const Color kSurfaceDark = Color(0xFF1C1C20);
  static const Color kSurfaceLight = Color(0xFFEEEEEE);
  static const Color kSurfaceContainerDark = Color(0xFF161616);
  static const Color kSurfaceContainerLight = Color(0xFFEEEEEE);
  static const Color kTextDark = Color(0xFFE9EAEE);
  static const Color kTextLight = Color(0xFF202125);
  static const Color kTextSecondaryDark = Color(0xFF9BA0A4);
  static const Color kTextSecondaryLight = Color(0xFF5F6267);
  static const Color kPrimary = Color(0xFF356AE6);
  static const Color kOngoing = Color(0xFFF53B66);
  static const Color kReaderBgDefault = Color(0xFF292832);
  static const Color kReaderTextDefault = Color(0xFFCCCCCC);

  static const Map<String, Color> kReaderBgColors = {
    'dark': Color(0xFF292832),
    'light': Color(0xFFFFF8E7),
    'sepia': Color(0xFFF5E6C8),
    'green': Color(0xFF1A2F1A),
    'blue': Color(0xFF1A1A2F),
  };

  static const Map<String, Color> kReaderTextColors = {
    'dark': Color(0xFFCCCCCC),
    'light': Color(0xFF333333),
    'sepia': Color(0xFF5B4636),
    'green': Color(0xFFC8E6C9),
    'blue': Color(0xFFC8C8FF),
  };

  static ThemeData dark({Color primary = kPrimary}) {
    final scheme = FlexColorScheme.dark(
      primary: primary,
      surface: kSurfaceDark,
      scaffoldBackground: kBackgroundDark,
      appBarBackground: kSurfaceVariantDark,
      subThemesData: const FlexSubThemesData(blendOnLevel: 10),
    );
    return scheme.toTheme;
  }

  static ThemeData light({Color primary = kPrimary}) {
    final scheme = FlexColorScheme.light(
      primary: primary,
      usedColors: 1,
      surface: kSurfaceLight,
      scaffoldBackground: kBackgroundLight,
      appBarBackground: kSurfaceVariantLight,
      subThemesData: const FlexSubThemesData(blendOnLevel: 10),
    );
    return scheme.toTheme;
  }

  static ThemeData amoled({Color primary = kPrimary}) {
    final scheme = FlexColorScheme.dark(
      primary: primary,
      surface: kBackgroundAmoled,
      scaffoldBackground: kBackgroundAmoled,
      appBarBackground: kSurfaceDark,
      subThemesData: const FlexSubThemesData(blendOnLevel: 10),
    );
    return scheme.toTheme;
  }

  static TextStyle readerText({
    double size = 16.0,
    Color color = kReaderTextDefault,
    double height = 1.6,
    String? fontFamily,
  }) {
    return TextStyle(
      fontSize: size,
      color: color,
      height: height,
      fontFamily: fontFamily,
    );
  }

  static TextSpan bionicText(String text, TextStyle style) {
    final words = text.split(' ');
    final spans = <TextSpan>[];
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty) continue;
      final mid = (word.length / 2).ceil();
      spans.add(TextSpan(
        children: [
          TextSpan(
            text: word.substring(0, mid),
            style: style.copyWith(fontWeight: FontWeight.bold),
          ),
          TextSpan(
            text: word.substring(mid),
            style: style,
          ),
        ],
      ));
      if (i < words.length - 1) {
        spans.add(TextSpan(text: ' ', style: style));
      }
    }
    return TextSpan(children: spans);
  }
}
