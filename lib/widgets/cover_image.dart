import 'package:flutter/material.dart';

/// Reusable cover image widget with placeholder fallback.
class CoverImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Map<String, String>? imageHeaders;

  /// Screen-reader label, e.g. 'Cover of <title>'. Null marks the art
  /// decorative (placeholders always are).
  final String? semanticLabel;

  const CoverImage({
    super.key,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.imageHeaders,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel;
    final placeholder = ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: borderRadius,
        ),
        child: const Icon(Icons.book, size: 32),
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
