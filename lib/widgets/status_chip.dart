import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Reusable status chip for novel status (Reading, Completed, etc.).
/// Colors come from the [AppColors] extension so both modes stay tuned.
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (status.toLowerCase()) {
      'ongoing' || 'reading' => (appColors.ongoing, 'Ongoing'),
      'completed' => (appColors.completed, 'Completed'),
      'dropped' => (appColors.dropped, 'Dropped'),
      'on hold' => (appColors.onHold, 'On Hold'),
      _ => (scheme.onSurfaceVariant, status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.all(Radii.sm),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
