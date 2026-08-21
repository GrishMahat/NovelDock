import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// App-wide theme constants.
///
/// Accent (blue) is the app's seed for both light and dark schemes, so the
/// Material 3 color scheme derives from it. Reader-specific colors stay
/// here (reader prose must not follow the UI accent).
class AppTheme {
  /// Brand accent used to seed all light/dark color schemes.
  static const kAccentSeed = Color(0xFF356AE6);

  /// Backwards-compatible alias for callers that referenced the accent.
  static const kPrimary = kAccentSeed;

  // ── Reader palette (kept stable across light/dark; reader owns its look)
  static const Map<String, Color> kReaderBgColors = {
    'dark': Color(0xFF121212),
    'light': Color(0xFFE8E2D7),
    'sepia': Color(0xFFF4ECD8),
    'green': Color(0xFF1E2A38),
    'blue': Color(0xFF1A1A2F),
  };
  static const Map<String, Color> kReaderTextColors = {
    'dark': Color(0xFFCCCCCC),
    'light': Color(0xFF1F1F1F),
    'sepia': Color(0xFF3B3B2A),
    'green': Color(0xFF9FB8CC),
    'blue': Color(0xFFC8C8FF),
  };
  static const Color kReaderBgDefault = Color(0xFF121212);
  static const Color kReaderTextDefault = Color(0xFFCCCCCC);

  /// Theme for a reader background/text color pair.
  static ThemeData readerTheme(Color bg, Color text) {
    return ThemeData(
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kAccentSeed,
        brightness: ThemeData.estimateBrightnessForColor(bg),
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
    );
  }

  /// Text style for reader prose.
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

  /// Bionic reading: bold the first half of every word.
  static TextSpan bionicText(String text, TextStyle style) {
    final words = text.split(' ');
    final spans = <TextSpan>[];
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty) continue;
      final mid = (word.length / 2).ceil();
      spans.add(
        TextSpan(
          children: [
            TextSpan(
              text: word.substring(0, mid),
              style: style.copyWith(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: word.substring(mid), style: style),
          ],
        ),
      );
      if (i < words.length - 1) {
        spans.add(TextSpan(text: ' ', style: style));
      }
    }
    return TextSpan(children: spans);
  }

  static ThemeData dark({Color primary = kAccentSeed}) => _build(
    FlexColorScheme.dark(
      colors: FlexSchemeColor(
        primary: primary,
        secondary: primary,
        tertiary: Color(0xFF8AB4F8),
        primaryContainer: Color(0xFF16325C),
        secondaryContainer: Color(0xFF16325C),
        tertiaryContainer: Color(0xFF0B1E38),
        error: Color(0xFFF2B8B5),
        errorContainer: Color(0xFF8C1D18),
      ),
      surfaceMode: FlexSurfaceMode.level,
      blendLevel: 0,
      useMaterial3: true,
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    ),
  );

  static ThemeData light({Color primary = kAccentSeed}) => _build(
    FlexColorScheme.light(
      colors: FlexSchemeColor(
        primary: primary,
        secondary: primary,
        tertiary: Color(0xFF0B57D0),
        primaryContainer: Color(0xFFD6E4FF),
        secondaryContainer: Color(0xFFD6E4FF),
        tertiaryContainer: Color(0xFFD3E3FD),
        error: Color(0xFFB3261E),
        errorContainer: Color(0xFFF9DEDC),
      ),
      surfaceMode: FlexSurfaceMode.level,
      blendLevel: 0,
      useMaterial3: true,
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    ),
  );

  static ThemeData amoled({Color primary = kAccentSeed}) => _build(
    FlexColorScheme.dark(
      colors: FlexSchemeColor(
        primary: primary,
        secondary: primary,
        tertiary: Color(0xFF8AB4F8),
        primaryContainer: Color(0xFF16325C),
        secondaryContainer: Color(0xFF16325C),
        tertiaryContainer: Color(0xFF0B1E38),
        error: Color(0xFFF2B8B5),
        errorContainer: Color(0xFF8C1D18),
      ),
      surfaceMode: FlexSurfaceMode.level,
      blendLevel: 0,
      useMaterial3: true,
      visualDensity: FlexColorScheme.comfortablePlatformDensity,
    ),
    surfaceOverride: Colors.black,
    surfaceLayers: const {
      'lowest': Color(0xFF08080A),
      'low': Color(0xFF0E0E10),
      'default': Color(0xFF121214),
      'high': Color(0xFF17171A),
      'highest': Color(0xFF1D1D21),
    },
  );

  static ThemeData _build(
    FlexColorScheme scheme, {
    Color? surfaceOverride,
    Map<String, Color>? surfaceLayers,
    Color primary = kAccentSeed,
  }) {
    final base = scheme.toScheme;
    final schemeColors = base.copyWith(
      surface: surfaceOverride ?? base.surface,
      surfaceContainerLowest:
          surfaceLayers?['lowest'] ??
          surfaceOverride ??
          base.surfaceContainerLowest,
      surfaceContainerLow:
          surfaceLayers?['low'] ?? surfaceOverride ?? base.surfaceContainerLow,
      surfaceContainer:
          surfaceLayers?['default'] ?? surfaceOverride ?? base.surfaceContainer,
      surfaceContainerHigh:
          surfaceLayers?['high'] ??
          surfaceOverride ??
          base.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceLayers?['highest'] ??
          surfaceOverride ??
          base.surfaceContainerHighest,
      surfaceTint: primary,
    );
    final text = _textTheme(schemeColors);

    return scheme.toTheme.copyWith(
      colorScheme: schemeColors,
      textTheme: text,
      scaffoldBackgroundColor: schemeColors.surface,
      extensions: [AppColors.forBrightness(schemeColors.brightness)],
      appBarTheme: AppBarTheme(
        backgroundColor: schemeColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: schemeColors.onSurfaceVariant),
        actionsIconTheme: IconThemeData(color: schemeColors.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: schemeColors.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(color: schemeColors.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radii.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radii.md),
          ),
          side: BorderSide(color: schemeColors.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radii.md),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: schemeColors.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radii.md),
          borderSide: BorderSide(color: schemeColors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radii.md),
          borderSide: BorderSide(color: schemeColors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radii.md),
          borderSide: BorderSide(color: schemeColors.primary, width: 1.5),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: schemeColors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: schemeColors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        showDragHandle: true,
        dragHandleColor: schemeColors.outlineVariant,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: schemeColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: schemeColors.primaryContainer,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? schemeColors.onPrimaryContainer
                : schemeColors.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? schemeColors.onSurface
                : schemeColors.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: schemeColors.surface,
        indicatorColor: schemeColors.primaryContainer,
        selectedIconTheme: IconThemeData(
          color: schemeColors.onPrimaryContainer,
        ),
        unselectedIconTheme: IconThemeData(
          color: schemeColors.onSurfaceVariant,
        ),
        selectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: schemeColors.onSurface,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: schemeColors.onSurfaceVariant,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: schemeColors.inverseSurface,
        contentTextStyle: TextStyle(color: schemeColors.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.md)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: schemeColors.onSurface,
        unselectedLabelColor: schemeColors.onSurfaceVariant,
        indicatorColor: schemeColors.primary,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: schemeColors.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.md)),
      ),
      iconTheme: IconThemeData(color: schemeColors.onSurfaceVariant),
      dialogTheme: DialogThemeData(
        backgroundColor: schemeColors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.lg)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: schemeColors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radii.md)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: schemeColors.surfaceContainerHighest,
        selectedColor: schemeColors.primaryContainer,
        side: BorderSide(color: schemeColors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: schemeColors.onSurface,
        ),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    const sora = 'Sora';
    const platform = 'Literata';

    return const TextTheme(
      displaySmall: TextStyle(
        fontFamily: sora,
        fontSize: 32,
        height: 1.15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        fontFamily: sora,
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.25,
      ),
      headlineSmall: TextStyle(
        fontFamily: sora,
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        fontFamily: sora,
        fontSize: 17,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleMedium: TextStyle(
        fontFamily: sora,
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.05,
      ),
      titleSmall: TextStyle(
        fontFamily: sora,
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        fontFamily: platform,
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0.1,
      ),
      bodyMedium: TextStyle(
        fontFamily: platform,
        fontSize: 14,
        height: 1.45,
        letterSpacing: 0.1,
      ),
      bodySmall: TextStyle(
        fontFamily: platform,
        fontSize: 12,
        height: 1.4,
        letterSpacing: 0.1,
      ),
      labelLarge: TextStyle(
        fontFamily: sora,
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontFamily: sora,
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelSmall: TextStyle(
        fontFamily: sora,
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }
}

/// Semantic colors Material doesn't model: library statuses and state
/// colors. Lerps between modes; tuned per brightness (desaturated in dark).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color ongoing;
  final Color completed;
  final Color dropped;
  final Color onHold;

  const AppColors({
    required this.ongoing,
    required this.completed,
    required this.dropped,
    required this.onHold,
  });

  static AppColors forBrightness(Brightness brightness) {
    return brightness == Brightness.dark
        ? const AppColors(
            ongoing: Color(0xFF7FB069),
            completed: Color(0xFF7FA7C9),
            dropped: Color(0xFFC98A8A),
            onHold: Color(0xFFC9B17F),
          )
        : const AppColors(
            ongoing: Color(0xFF3E7D2F),
            completed: Color(0xFF3E6B8C),
            dropped: Color(0xFF9C4A4A),
            onHold: Color(0xFF8C7433),
          );
  }

  @override
  AppColors copyWith({
    Color? ongoing,
    Color? completed,
    Color? dropped,
    Color? onHold,
  }) {
    return AppColors(
      ongoing: ongoing ?? this.ongoing,
      completed: completed ?? this.completed,
      dropped: dropped ?? this.dropped,
      onHold: onHold ?? this.onHold,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      ongoing: Color.lerp(ongoing, other.ongoing, t)!,
      completed: Color.lerp(completed, other.completed, t)!,
      dropped: Color.lerp(dropped, other.dropped, t)!,
      onHold: Color.lerp(onHold, other.onHold, t)!,
    );
  }
}
