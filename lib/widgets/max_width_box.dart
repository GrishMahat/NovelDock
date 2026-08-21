import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Centers [child] horizontally and constrains it to [Desktop.maxContentWidth]
/// on wide screens. Content keeps its natural width below the breakpoint.
class MaxWidthBox extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  const MaxWidthBox({
    super.key,
    required this.child,
    this.maxWidth = Desktop.maxContentWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: Insets.md),
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}