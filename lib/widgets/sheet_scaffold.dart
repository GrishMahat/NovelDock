import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// Title + content + Cancel/primary footer for bottom-sheet pickers.
///
/// Scrollable because the content plus the action row can exceed a short
/// window (landscape phone), where a bare Column overflowed with the buttons
/// cut off.
Widget sheetScaffold(
  BuildContext context, {
  required String title,
  required List<Widget> children,
  required Widget primary,
}) {
  return SafeArea(
    child: SingleChildScrollView(
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
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
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
                Expanded(child: primary),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
