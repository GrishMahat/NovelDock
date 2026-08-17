import 'package:flutter/material.dart';

import '../core/providers/engine.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';

/// Reusable novel result card in a grid.
class NovelGridCard extends StatelessWidget {
  final SearchResultItem item;
  final VoidCallback onTap;
  final bool showProvider;

  const NovelGridCard({
    super.key,
    required this.item,
    required this.onTap,
    this.showProvider = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CoverImage(
                imageUrl: item.cover,
                fit: BoxFit.cover,
                imageHeaders: item.coverHeaders,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showProvider && item.providerId != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.providerId!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable novel result as a list tile.
class NovelListTile extends StatelessWidget {
  final SearchResultItem item;
  final VoidCallback onTap;
  final String? subtitleOverride;

  const NovelListTile({
    super.key,
    required this.item,
    required this.onTap,
    this.subtitleOverride,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: CoverImage(
          imageUrl: item.cover,
          width: 48,
          height: 64,
          imageHeaders: item.coverHeaders,
        ),
      ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitleOverride ??
            [
              if (item.author != null) item.author!,
              if (item.latestChapter != null) 'Ch. ${item.latestChapter}',
            ].join(' · '),
        style: const TextStyle(fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: item.rating != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, size: 14, color: Colors.amber),
                const SizedBox(width: 2),
                Text('${item.rating}', style: const TextStyle(fontSize: 12)),
              ],
            )
          : null,
      onTap: onTap,
    );
  }
}

/// Compact one-line novel result.
class NovelCompactTile extends StatelessWidget {
  final SearchResultItem item;
  final VoidCallback onTap;

  const NovelCompactTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CoverImage(
                imageUrl: item.cover,
                width: 28,
                height: 38,
                imageHeaders: item.coverHeaders,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (item.author != null)
                    Text(
                      item.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.kTextSecondaryDark,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}