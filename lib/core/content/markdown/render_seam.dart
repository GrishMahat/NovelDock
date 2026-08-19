import 'package:flutter/material.dart';

/// Narrow view of the reader's settings consumed by the markdown renderer.
///
/// The caller (reader feature) resolves defaults, including the default
/// font, before constructing this, so core stays free of feature-side
/// constants. See `ReaderSettings.asRenderSettings()` in the reader feature.
class ReaderRenderSettings {
  final double fontSize;
  final String fontFamily;
  final double lineHeight;
  final Color textColor;
  final String textAlignment;
  final double paragraphSpacing;
  final bool bionicReading;

  const ReaderRenderSettings({
    required this.fontSize,
    required this.fontFamily,
    required this.lineHeight,
    required this.textColor,
    required this.textAlignment,
    required this.paragraphSpacing,
    required this.bionicReading,
  });
}

/// How a paragraph is highlighted while TTS is speaking.
enum TtsHighlightStyle { sentence, paragraph, none }

/// Narrow view of TTS playback state consumed by the markdown renderer.
///
/// Built by the reader feature from `TtsManagerState`; the renderer never
/// depends on the TTS module's state shape.
class TtsHighlightState {
  final bool isSpeaking;
  final int currentChunkIndex;
  final int currentWordIndex;
  final TtsHighlightStyle highlightStyle;

  const TtsHighlightState({
    required this.isSpeaking,
    required this.currentChunkIndex,
    required this.currentWordIndex,
    required this.highlightStyle,
  });
}