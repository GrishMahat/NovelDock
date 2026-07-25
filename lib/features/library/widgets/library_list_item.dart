import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../theme/app_theme.dart';

/// List item for library screen — cover thumbnail + title + author + play button.
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
        child: _buildCover(48, 64),
      ),
      title: Text(novel.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [novel.author, novel.status].where((s) => s != null && s.isNotEmpty).join(' · '),
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.play_circle_outline, size: 28),
        color: AppTheme.kPrimary,
        onPressed: onPlay,
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget _buildCover(double width, double height) {
    if (novel.coverUrl != null && novel.coverUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: novel.coverUrl!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(width: width, height: height, color: AppTheme.kSurfaceVariantDark, child: const Icon(Icons.book, size: 32)),
        errorWidget: (_, __, ___) => Container(width: width, height: height, color: AppTheme.kSurfaceVariantDark, child: const Icon(Icons.book, size: 32)),
      );
    }
    return Container(width: width, height: height, color: AppTheme.kSurfaceVariantDark, child: const Icon(Icons.book, size: 32));
  }
}
