import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../theme/app_theme.dart';

/// Continue reading card — shows the most recently read novel with progress.
class ContinueReadingCard extends StatelessWidget {
  final Novel novel;
  final String? chapterName;
  final double progress;
  final VoidCallback onTap;

  const ContinueReadingCard({
    super.key,
    required this.novel,
    this.chapterName,
    this.progress = 0.0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            // Cover
            SizedBox(
              width: 60,
              height: 80,
              child: novel.coverUrl != null && novel.coverUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: novel.coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppTheme.kSurfaceVariantDark, child: const Icon(Icons.book, size: 24)),
                      errorWidget: (_, __, ___) => Container(color: AppTheme.kSurfaceVariantDark, child: const Icon(Icons.book, size: 24)),
                    )
                  : Container(color: AppTheme.kSurfaceVariantDark, child: const Icon(Icons.book, size: 24)),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(novel.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (chapterName != null) ...[
                      const SizedBox(height: 4),
                      Text(chapterName!, style: TextStyle(fontSize: 12, color: AppTheme.kTextSecondaryDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 3),
                    const SizedBox(height: 2),
                    Text('${(progress * 100).round()}%', style: TextStyle(fontSize: 10, color: AppTheme.kTextSecondaryDark)),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}
