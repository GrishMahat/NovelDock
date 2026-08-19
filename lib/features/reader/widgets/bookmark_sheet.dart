import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../theme/app_theme.dart';

/// Shows a dialog asking the user for an optional bookmark note.
/// Returns the note text, or null if cancelled.
Future<String?> showAddBookmarkDialog(
  BuildContext context, {
  required String chapterName,
}) {
  final noteController = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add Bookmark'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chapterName,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteController,
            decoration: const InputDecoration(
              hintText: 'Add a note (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, noteController.text),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(() => noteController.dispose());
}

/// Formats a millisecond epoch timestamp as a local "HH:mm" string
/// without relying on DateTime.toString()'s exact output format.
String _formatTime(int epochMillis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMillis).toLocal();
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Shows a draggable bottom sheet listing bookmarks for the current novel.
///
/// [onTapBookmark] receives the chapter index and an optional scroll position
/// (0.0–1.0) so the caller can navigate to the bookmarked location.
/// [onDeleteBookmark] is called with the bookmark id when the user deletes one.
void showBookmarkSheet({
  required BuildContext context,
  required List<Bookmark> bookmarks,
  required List<Chapter> chapters,
  required void Function(int chapterIndex, double scrollPosition) onTapBookmark,
  required Future<void> Function(int bookmarkId) onDeleteBookmark,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.4,
      maxChildSize: 0.7,
      minChildSize: 0.2,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Bookmarks',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: bookmarks.length,
              itemBuilder: (context, index) {
                final bm = bookmarks[index];

                Chapter? chapter;
                for (final c in chapters) {
                  if (c.id == bm.chapterId) {
                    chapter = c;
                    break;
                  }
                }
                // If the chapter this bookmark points to no longer exists
                // (deleted/renumbered), skip rendering it rather than
                // silently falling back to chapter 0's name, which would
                // misleadingly point the user at the wrong chapter.
                if (chapter == null) {
                  return const SizedBox.shrink();
                }
                final resolvedChapter = chapter;

                final position =
                    (double.tryParse(bm.position ?? '0') ?? 0) * 100;
                final time = _formatTime(bm.createdAt);

                return ListTile(
                  leading: const Icon(Icons.bookmark, color: AppTheme.kPrimary),
                  title: Text(
                    resolvedChapter.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Position: ${position.round()}% · $time',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (bm.note != null && bm.note!.isNotEmpty)
                        Text(
                          bm.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.kPrimary.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () async {
                      await onDeleteBookmark(bm.id);
                    },
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    final chIdx = chapters.indexWhere(
                      (c) => c.id == bm.chapterId,
                    );
                    if (chIdx >= 0) {
                      final pos = double.tryParse(bm.position ?? '0') ?? 0;
                      onTapBookmark(chIdx, pos);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
