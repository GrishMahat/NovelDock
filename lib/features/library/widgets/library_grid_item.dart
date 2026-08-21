import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';

/// Grid item for library screen. Book cover + status chip + title + play
/// button overlay. Colors come from the theme; the play button uses
/// `primary` so it survives both brightness modes.
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = novel.status;

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
                  _buildCover(context),
                  if (status != null && status.isNotEmpty)
                    Positioned(
                      left: Insets.xs,
                      top: Insets.xs,
                      child: _StatusChip(label: status),
                    ),
                  Positioned(
                    right: Insets.xs,
                    bottom: Insets.xs,
                    child: Material(
                      color: scheme.primary,
                      shape: const CircleBorder(),
                      elevation: 2,
                      child: InkWell(
                        onTap: onPlay,
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.play_arrow,
                            size: 20,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.sm),
              child: Text(
                novel.title,
                style: text.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    final fallback = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.book, size: 32),
    );
    if (novel.coverUrl == null || novel.coverUrl!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: novel.coverUrl!,
      fit: BoxFit.cover,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}

/// Small status pill drawn on the cover corner. Color comes from the
/// semantic AppColors extension (library status colors).
class _StatusChip extends StatelessWidget {
  final String label;
  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>();
    final scheme = Theme.of(context).colorScheme;

    final Color color;
    switch (label) {
      case 'Reading':
        color = appColors?.ongoing ?? scheme.primary;
        break;
      case 'Completed':
        color = appColors?.completed ?? scheme.primary;
        break;
      case 'Dropped':
        color = appColors?.dropped ?? scheme.primary;
        break;
      case 'On Hold':
        color = appColors?.onHold ?? scheme.primary;
        break;
      default:
        color = scheme.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.all(Radii.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
