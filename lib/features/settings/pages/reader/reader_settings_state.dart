import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/logger.dart';
import '../../../../theme/app_theme.dart';

const _tag = 'ReaderSettings';

/// Bundled default reader font (Literata, OFL license — designed for on-screen book reading).
const String kDefaultReaderFont = 'Literata';

class ReaderSettings {
  final double fontSize;
  final String fontFamily;
  final double lineHeight;
  final double paddingH;
  final double paddingV;
  final String scrollMode;
  final String textAlignment;
  final double paragraphSpacing;
  final bool bionicReading;
  final bool showTime;
  final bool showBattery;
  final bool keepScreenOn;
  final bool selectableText;
  final bool ttsAutoScroll;
  final bool ttsAutoAdvance;
  final String orientation;
  final String readerTheme;
  final String leftTapAction;
  final String centerTapAction;
  final String rightTapAction;

  const ReaderSettings({
    this.fontSize = 16.0,
    this.fontFamily = kDefaultReaderFont,
    this.lineHeight = 1.6,
    this.paddingH = 24.0,
    this.paddingV = 24.0,
    this.scrollMode = 'continuous',
    this.textAlignment = 'justify',
    this.paragraphSpacing = 12.0,
    this.bionicReading = false,
    this.showTime = true,
    this.showBattery = true,
    this.keepScreenOn = true,
    this.selectableText = false,
    this.ttsAutoScroll = true,
    this.ttsAutoAdvance = true,
    this.orientation = 'auto',
    this.readerTheme = 'dark',
    this.leftTapAction = 'previous',
    this.centerTapAction = 'menu',
    this.rightTapAction = 'next',
  });

  ReaderSettings copyWith({
    double? fontSize,
    String? fontFamily,
    double? lineHeight,
    double? paddingH,
    double? paddingV,
    String? scrollMode,
    String? textAlignment,
    double? paragraphSpacing,
    bool? bionicReading,
    bool? showTime,
    bool? showBattery,
    bool? keepScreenOn,
    bool? selectableText,
    bool? ttsAutoScroll,
    bool? ttsAutoAdvance,
    String? orientation,
    String? readerTheme,
    String? leftTapAction,
    String? centerTapAction,
    String? rightTapAction,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      lineHeight: lineHeight ?? this.lineHeight,
      paddingH: paddingH ?? this.paddingH,
      paddingV: paddingV ?? this.paddingV,
      scrollMode: scrollMode ?? this.scrollMode,
      textAlignment: textAlignment ?? this.textAlignment,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      bionicReading: bionicReading ?? this.bionicReading,
      showTime: showTime ?? this.showTime,
      showBattery: showBattery ?? this.showBattery,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      selectableText: selectableText ?? this.selectableText,
      ttsAutoScroll: ttsAutoScroll ?? this.ttsAutoScroll,
      ttsAutoAdvance: ttsAutoAdvance ?? this.ttsAutoAdvance,
      orientation: orientation ?? this.orientation,
      readerTheme: readerTheme ?? this.readerTheme,
      leftTapAction: leftTapAction ?? this.leftTapAction,
      centerTapAction: centerTapAction ?? this.centerTapAction,
      rightTapAction: rightTapAction ?? this.rightTapAction,
    );
  }

  Color get bgColor {
    switch (readerTheme) {
      case 'light':
        return AppTheme.kReaderBgColors['light']!;
      case 'sepia':
        return AppTheme.kReaderBgColors['sepia']!;
      case 'green':
        return AppTheme.kReaderBgColors['green']!;
      case 'blue':
        return AppTheme.kReaderBgColors['blue']!;
      default:
        return AppTheme.kReaderBgDefault;
    }
  }

  Color get textColor {
    switch (readerTheme) {
      case 'light':
        return AppTheme.kReaderTextColors['light']!;
      case 'sepia':
        return AppTheme.kReaderTextColors['sepia']!;
      case 'green':
        return AppTheme.kReaderTextColors['green']!;
      case 'blue':
        return AppTheme.kReaderTextColors['blue']!;
      default:
        return AppTheme.kReaderTextDefault;
    }
  }
}

Future<List<String>> getSystemFonts() async {
  try {
    if (Platform.isLinux) {
      final result = await Process.run('fc-list', ['--format=%{family}\n']);
      if (result.exitCode == 0) {
        final seen = <String>{};
        final fonts = <String>[];
        for (final line in (result.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          for (final family in trimmed.split(',')) {
            final name = family.trim();
            if (name.isNotEmpty && seen.add(name.toLowerCase())) {
              fonts.add(name);
            }
          }
        }
        fonts.sort();
        return fonts;
      }
    }
    if (Platform.isWindows) {
      final result = await Process.run('reg', [
        'query',
        'HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts',
        '/s',
      ]);
      if (result.exitCode == 0) {
        final fonts = <String>{};
        final lines = (result.stdout as String).split('\n');
        for (final line in lines) {
          final match = RegExp(r'\((.+?)\)').firstMatch(line);
          if (match != null) fonts.add(match.group(1)!);
        }
        final sorted = fonts.toList()..sort();
        return sorted;
      }
    }
  } catch (e) {
    Log.e(_tag, 'Failed to get system fonts', e);
  }
  return [
    'Literata',
    'Arial',
    'Courier New',
    'Georgia',
    'Helvetica',
    'Times New Roman',
    'Trebuchet MS',
    'Verdana',
    'Consolas',
    'Lucida Console',
  ];
}

class ReaderSettingsNotifier extends StateNotifier<ReaderSettings> {
  ReaderSettingsNotifier() : super(const ReaderSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final storedFont = p.getString('reader_font_family');
      state = ReaderSettings(
        fontSize: p.getDouble('reader_font_size') ?? 16.0,
        fontFamily: (storedFont == null || storedFont.isEmpty)
            ? kDefaultReaderFont
            : storedFont,
        lineHeight: p.getDouble('reader_line_height') ?? 1.6,
        paddingH: p.getDouble('reader_padding_h') ?? 24.0,
        paddingV: p.getDouble('reader_padding_v') ?? 24.0,
        scrollMode: p.getString('reader_scroll_mode') ?? 'continuous',
        textAlignment: p.getString('reader_text_alignment') ?? 'justify',
        paragraphSpacing: p.getDouble('reader_paragraph_spacing') ?? 12.0,
        bionicReading: p.getBool('reader_bionic_reading') ?? false,
        showTime: p.getBool('reader_show_time') ?? true,
        showBattery: p.getBool('reader_show_battery') ?? true,
        keepScreenOn: p.getBool('reader_keep_screen_on') ?? true,
        selectableText: p.getBool('reader_selectable_text') ?? false,
        ttsAutoScroll: p.getBool('reader_tts_autoscroll') ?? true,
        ttsAutoAdvance: p.getBool('reader_tts_autoadvance') ?? true,
        orientation: p.getString('reader_orientation') ?? 'auto',
        readerTheme: p.getString('reader_theme') ?? 'dark',
        leftTapAction: p.getString('reader_left_tap') ?? 'previous',
        centerTapAction: p.getString('reader_center_tap') ?? 'menu',
        rightTapAction: p.getString('reader_right_tap') ?? 'next',
      );
    } catch (e) {
      Log.e(_tag, 'Failed to load settings', e);
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('reader_font_size', state.fontSize);
      await p.setString('reader_font_family', state.fontFamily);
      await p.setDouble('reader_line_height', state.lineHeight);
      await p.setDouble('reader_padding_h', state.paddingH);
      await p.setDouble('reader_padding_v', state.paddingV);
      await p.setString('reader_scroll_mode', state.scrollMode);
      await p.setString('reader_text_alignment', state.textAlignment);
      await p.setDouble('reader_paragraph_spacing', state.paragraphSpacing);
      await p.setBool('reader_bionic_reading', state.bionicReading);
      await p.setBool('reader_show_time', state.showTime);
      await p.setBool('reader_show_battery', state.showBattery);
      await p.setBool('reader_keep_screen_on', state.keepScreenOn);
      await p.setBool('reader_selectable_text', state.selectableText);
      await p.setBool('reader_tts_autoscroll', state.ttsAutoScroll);
      await p.setBool('reader_tts_autoadvance', state.ttsAutoAdvance);
      await p.setString('reader_orientation', state.orientation);
      await p.setString('reader_theme', state.readerTheme);
      await p.setString('reader_left_tap', state.leftTapAction);
      await p.setString('reader_center_tap', state.centerTapAction);
      await p.setString('reader_right_tap', state.rightTapAction);
    } catch (e) {
      Log.e(_tag, 'Failed to save settings', e);
    }
  }

  void _update(ReaderSettings Function(ReaderSettings) updater) {
    state = updater(state);
    _save();
  }

  void updateFontSize(double v) => _update((s) => s.copyWith(fontSize: v));
  void updateFontFamily(String v) => _update((s) => s.copyWith(fontFamily: v));
  void updateLineHeight(double v) => _update((s) => s.copyWith(lineHeight: v));
  void updatePaddingH(double v) => _update((s) => s.copyWith(paddingH: v));
  void updatePaddingV(double v) => _update((s) => s.copyWith(paddingV: v));
  void updateScrollMode(String v) => _update((s) => s.copyWith(scrollMode: v));
  void updateTextAlignment(String v) =>
      _update((s) => s.copyWith(textAlignment: v));
  void updateParagraphSpacing(double v) =>
      _update((s) => s.copyWith(paragraphSpacing: v));
  void updateOrientation(String v) =>
      _update((s) => s.copyWith(orientation: v));
  void updateReaderTheme(String v) =>
      _update((s) => s.copyWith(readerTheme: v));
  void toggleBionicReading() =>
      _update((s) => s.copyWith(bionicReading: !s.bionicReading));
  void toggleShowTime() => _update((s) => s.copyWith(showTime: !s.showTime));
  void toggleShowBattery() =>
      _update((s) => s.copyWith(showBattery: !s.showBattery));
  void toggleKeepScreenOn() =>
      _update((s) => s.copyWith(keepScreenOn: !s.keepScreenOn));
  void toggleSelectableText() =>
      _update((s) => s.copyWith(selectableText: !s.selectableText));
  void toggleTtsAutoScroll() =>
      _update((s) => s.copyWith(ttsAutoScroll: !s.ttsAutoScroll));
  void toggleTtsAutoAdvance() =>
      _update((s) => s.copyWith(ttsAutoAdvance: !s.ttsAutoAdvance));
  void updateLeftTapAction(String v) =>
      _update((s) => s.copyWith(leftTapAction: v));
  void updateCenterTapAction(String v) =>
      _update((s) => s.copyWith(centerTapAction: v));
  void updateRightTapAction(String v) =>
      _update((s) => s.copyWith(rightTapAction: v));
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettings>((ref) {
      return ReaderSettingsNotifier();
    });
