import 'package:flutter/material.dart';

import '../../../core/database/database.dart';

/// Bottom sheet for a long-pressed reader paragraph: highlight it, attach a
/// note, or manage an existing annotation. All persistence flows back
/// through the callbacks so this widget stays stateless w.r.t. Riverpod.
Future<void> showAnnotationSheet(
  BuildContext context, {
  required Annotation? existing,
  required String quote,
  required Future<void> Function() onHighlight,
  required Future<void> Function(String note) onSaveNote,
  required Future<void> Function() onRemove,
}) {
  final preview = quote.length > 160 ? '${quote.substring(0, 160)}…' : quote;
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  preview.isEmpty ? 'Selected paragraph' : '“$preview”',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
              if (existing?.note != null && existing!.note!.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    existing.note!,
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (existing == null) ...[
                ListTile(
                  leading: const Icon(Icons.highlight),
                  title: const Text('Highlight paragraph'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await onHighlight();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.note_add_outlined),
                  title: const Text('Add a note…'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    if (!context.mounted) return;
                    final note = await _askNote(context);
                    if (note != null) await onSaveNote(note);
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(
                    existing.note == null || existing.note!.isEmpty
                        ? 'Add a note…'
                        : 'Edit note…',
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    if (!context.mounted) return;
                    final note = await _askNote(
                      context,
                      initial: existing.note,
                    );
                    if (note != null) await onSaveNote(note);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.highlight_remove,
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                  title: Text(
                    'Remove highlight',
                    style: TextStyle(
                      color: Theme.of(sheetContext).colorScheme.error,
                    ),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await onRemove();
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// Note editor dialog. Returns the text, null on cancel, and never an
/// empty string (clearing a note = removing it via the sheet).
Future<String?> _askNote(BuildContext context, {String? initial}) async {
  final controller = TextEditingController(text: initial ?? '');
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'What struck you about this passage?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((value) {
      if (value == null || value.isEmpty) return null;
      return value;
    });
  } finally {
    controller.dispose();
  }
}
