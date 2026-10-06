import 'package:material_ui/material_ui.dart';

import '../../../core/database/database.dart';

/// Shows a draggable bottom sheet listing all chapters.
void showChapterListSheet({
  required BuildContext context,
  required List<Chapter> chapters,
  required int currentIndex,
  required void Function(int index) onJumpToChapter,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.8,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Chapters',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final ch = chapters[index];
                final isCurrent = index == currentIndex;
                return ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: isCurrent
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.2)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Text(
                      '${index + 1}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: isCurrent
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ),
                  title: Text(
                    ch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isCurrent
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onJumpToChapter(index);
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
