import 'package:flutter/material.dart';

/// Letter tile shown when a novel has no cover (or it fails to load):
/// the title initial on a stable tint derived from the title, instead of a
/// generic book icon that makes every coverless novel look identical.
class CoverMonogram extends StatelessWidget {
  final String title;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final double fontSize;

  const CoverMonogram({
    super.key,
    required this.title,
    this.width,
    this.height,
    this.borderRadius,
    this.fontSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = title.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    // Stable hue per title so each novel keeps its own tile color.
    final hue = (title.hashCode.toUnsigned(32) % 360).toDouble();
    final tint = HSLColor.fromAHSL(1.0, hue, 0.45, 0.42).toColor();
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.18),
        borderRadius: borderRadius,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: tint,
          ),
        ),
      ),
    );
  }
}

/// Reusable cover image widget with monogram fallback.
class CoverImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Map<String, String>? imageHeaders;

  /// Screen-reader label, e.g. 'Cover of <title>'. Null marks the art
  /// decorative (monograms always are — the adjacent title text carries it).
  final String? semanticLabel;

  /// Title used for the monogram fallback. Null keeps the legacy book icon.
  final String? title;

  /// Monogram letter size. Scale to the tile (28px tiles want ~16).
  final double fontSize;

  const CoverImage({
    super.key,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.imageHeaders,
    this.semanticLabel,
    this.title,
    this.fontSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel;
    final fallbackTitle = title;
    final placeholder = ExcludeSemantics(
      child: fallbackTitle == null
          ? Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: borderRadius,
              ),
              child: const Icon(Icons.book, size: 32),
            )
          : CoverMonogram(
              title: fallbackTitle,
              width: width,
              height: height,
              borderRadius: borderRadius,
              fontSize: fontSize,
            ),
    );

    final Widget art;
    if (imageUrl == null || imageUrl!.isEmpty) {
      art = placeholder;
    } else {
      art = ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: Image.network(
          imageUrl!,
          width: width,
          height: height,
          fit: fit,
          headers: imageHeaders,
          excludeFromSemantics: label == null,
          errorBuilder: (_, _, _) => placeholder,
        ),
      );
    }

    if (label == null) return art;
    return Semantics(image: true, label: label, child: art);
  }
}
