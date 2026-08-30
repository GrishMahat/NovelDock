import 'package:epubx_kuebiko/epubx_kuebiko.dart';
import 'package:flutter/material.dart';

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

/// Shows a draggable bottom sheet with the EPUB table of contents.
void showEpubTocSheet({
  required BuildContext context,
  required List<EpubNavigationPoint> epubToc,
  required List<Chapter> chapters,
  required void Function(int index) onJumpToChapter,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.8,
      minChildSize: 0.2,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Table of Contents',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: epubToc.length,
              itemBuilder: (sheetContext, index) => buildTocEntry(
                context: sheetContext,
                point: epubToc[index],
                depth: 0,
                chapters: chapters,
                onJumpToChapter: onJumpToChapter,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Returns just the filename portion of a path/URL, with any query
/// string or fragment stripped, used to compare EPUB TOC `href`s
/// against chapter URLs without false-positive substring matches
/// (e.g. "ch1.html" incorrectly matching inside "ch10.html").
String _fileNameOf(String pathOrUrl) {
  final withoutFragment = pathOrUrl.split('#').first.split('?').first;
  final segments = withoutFragment.split('/');
  return segments.isNotEmpty ? segments.last : withoutFragment;
}

/// Builds a single TOC entry (and its children recursively).
Widget buildTocEntry({
  required BuildContext context,
  required EpubNavigationPoint point,
  required int depth,
  required List<Chapter> chapters,
  required void Function(int index) onJumpToChapter,
}) {
  final title = point.NavigationLabels?.isNotEmpty == true
      ? point.NavigationLabels!.first.Text ?? 'Untitled'
      : 'Untitled';
  final source = point.Content?.Source ?? '';

  int? chapterIndex;
  if (source.isNotEmpty) {
    final sourceFileName = _fileNameOf(source);
    for (var i = 0; i < chapters.length; i++) {
      if (_fileNameOf(chapters[i].url) == sourceFileName) {
        chapterIndex = i;
        break;
      }
    }
  }

  final children = point.ChildNavigationPoints;
  final hasChildren = children != null && children.isNotEmpty;
  final isDisabled = chapterIndex == null;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(
        contentPadding: EdgeInsets.only(left: 16.0 + depth * 20.0, right: 16.0),
        dense: true,
        enabled: !isDisabled,
        leading: hasChildren
            ? Icon(
                Icons.folder,
                size: 18,
                color: isDisabled
                    ? Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                    : null,
              )
            : null,
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: depth == 0 ? 14 : 13,
            fontWeight: depth == 0 ? FontWeight.w500 : FontWeight.normal,
            color: isDisabled
                ? Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                : null,
          ),
        ),
        onTap: isDisabled
            ? null
            : () {
                Navigator.pop(context);
                onJumpToChapter(chapterIndex!);
              },
      ),
      if (hasChildren)
        for (final child in children)
          buildTocEntry(
            context: context,
            point: child,
            depth: depth + 1,
            chapters: chapters,
            onJumpToChapter: onJumpToChapter,
          ),
    ],
  );
}
