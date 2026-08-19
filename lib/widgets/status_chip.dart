import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable status chip for novel status (Ongoing, Completed, etc.).
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status.toLowerCase()) {
      'ongoing' => (Theme.of(context).extension<AppColors>()!.ongoing, 'Ongoing'),
      'completed' => (Colors.green, 'Completed'),
      'dropped' => (Colors.red, 'Dropped'),
      _ => (Theme.of(context).colorScheme.onSurfaceVariant, status),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
