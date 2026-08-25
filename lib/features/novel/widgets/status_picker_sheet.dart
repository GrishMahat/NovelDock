import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';

/// Unified sheet for picking a library status. Returns the chosen status
/// string, 'None' to remove from library, or null if dismissed.
class StatusPickerSheet extends StatefulWidget {
  final String title;
  final String? initialStatus;

  const StatusPickerSheet({
    super.key,
    this.title = 'Library status',
    this.initialStatus,
  });

  @override
  State<StatusPickerSheet> createState() => _StatusPickerSheetState();
}

class _StatusPickerSheetState extends State<StatusPickerSheet> {
  static const _options = [
    ('Reading', Icons.auto_stories),
    ('On Hold', Icons.pause_circle_outline),
    ('Plan to Read', Icons.bookmark_border),
    ('Completed', Icons.check_circle_outline),
    ('Dropped', Icons.remove_circle_outline),
  ];

  late String? _selected = widget.initialStatus;
  bool _removeRequested = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>()!;
    Color? optionColor(String status) => switch (status.toLowerCase()) {
      'reading' => appColors.ongoing,
      'on hold' => appColors.onHold,
      'completed' => appColors.completed,
      'dropped' => appColors.dropped,
      _ => scheme.onSurfaceVariant,
    };

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.xl,
              Insets.xs,
              Insets.xl,
              Insets.sm,
            ),
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final (status, icon) in _options)
            ListTile(
              leading: Icon(icon, color: optionColor(status)),
              title: Text(status),
              selected: !_removeRequested && _selected == status,
              trailing:
                  !_removeRequested && _selected == status
                  ? const Icon(Icons.check, size: 20)
                  : null,
              onTap: () => setState(() {
                _selected = status;
                _removeRequested = false;
              }),
            ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: scheme.error),
            title: Text(
              'Remove from library',
              style: TextStyle(color: scheme.error),
            ),
            trailing: _removeRequested
                ? const Icon(Icons.check, size: 20)
                : null,
            onTap: () => setState(() => _removeRequested = true),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: Insets.lg,
              right: Insets.lg,
              top: Insets.sm,
              bottom: MediaQuery.paddingOf(context).bottom + Insets.lg,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      _removeRequested ? 'None' : _selected,
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
