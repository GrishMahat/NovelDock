import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../widgets/cover_image.dart';

/// List item for library screen. Cover thumbnail + title + author + play button.
class LibraryListItem extends StatelessWidget {
  final Novel novel;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback? onLongPress;

  const LibraryListItem({
    super.key,
    required this.novel,
    required this.onTap,
    required this.onPlay,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: _buildCover(context, 48, 64),
      ),
      title: Text(novel.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          novel.author,
          novel.status,
        ].where((s) => s != null && s.isNotEmpty).join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_outline, size: 28),
        color: Theme.of(context).colorScheme.primary,
        tooltip: 'Resume reading',
        onPressed: onPlay,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget _buildCover(BuildContext context, double width, double height) {
    // CoverImage handles remote URLs, local EPUB covers, and the monogram
    // fallback (CachedNetworkImage errors on file paths, showing the
    // monogram instead of the real local cover).
    return CoverImage(
      imageUrl: novel.coverUrl,
      title: novel.title,
      width: width,
      height: height,
      fontSize: 24,
      semanticLabel: 'Cover of ${novel.title}',
    );
  }
}
