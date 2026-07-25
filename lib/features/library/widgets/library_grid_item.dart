import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../theme/app_theme.dart';

/// Grid item for library screen — book cover + title + play button overlay.
class LibraryGridItem extends StatelessWidget {
  final Novel novel;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback? onLongPress;

  const LibraryGridItem({
    super.key,
    required this.novel,
    required this.onTap,
    required this.onPlay,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: GestureDetector(
                      onTap: onPlay,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppTheme.kPrimary,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4)],
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(novel.title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover() {
    if (novel.coverUrl != null && novel.coverUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: novel.coverUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: AppTheme.kSurfaceVariantDark, child: const Icon(Icons.book, size: 32)),
        errorWidget: (_, __, ___) => Container(color: AppTheme.kSurfaceVariantDark, child: const Icon(Icons.book, size: 32)),
      );
    }
    return Container(color: AppTheme.kSurfaceVariantDark, child: const Icon(Icons.book, size: 32));
  }
}
