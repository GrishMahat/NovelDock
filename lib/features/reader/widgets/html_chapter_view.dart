import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../../../theme/app_theme.dart';

/// Renders HTML chapter content with customizable styling.
class HtmlChapterView extends StatelessWidget {
  final String html;
  final double fontSize;
  final String fontFamily;
  final double lineHeight;
  final String textAlign;
  final double paddingH;
  final double paddingV;
  final double paragraphSpacing;
  final Color textColor;
  final bool selectableText;
  final int settingsVersion;

  const HtmlChapterView({
    super.key,
    required this.html,
    this.fontSize = 16.0,
    this.fontFamily = '',
    this.lineHeight = 1.6,
    this.textAlign = 'justify',
    this.paddingH = 24.0,
    this.paddingV = 24.0,
    this.paragraphSpacing = 12.0,
    this.textColor = AppTheme.kReaderTextDefault,
    this.selectableText = false,
    this.settingsVersion = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      child: HtmlWidget(
        html,
        key: ValueKey('html-$settingsVersion'),
        textStyle: TextStyle(
          fontSize: fontSize,
          fontFamily: fontFamily.isEmpty ? null : fontFamily,
          height: lineHeight,
          color: textColor,
        ),
        customStylesBuilder: (element) {
          final alignment = switch (textAlign) {
            'left' => TextAlign.left,
            'center' => TextAlign.center,
            'right' => TextAlign.right,
            'justify' => TextAlign.justify,
            _ => TextAlign.justify,
          };
          return {
            'text-align': textAlign,
            'line-height': lineHeight.toString(),
            'margin-bottom': '${paragraphSpacing}px',
          };
        },
      ),
    );
  }
}
