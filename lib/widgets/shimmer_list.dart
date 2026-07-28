import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_theme.dart';

class ShimmerGrid extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;
  final double aspectRatio;
  const ShimmerGrid({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 3,
    this.aspectRatio = 0.68,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: aspectRatio,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: itemCount,
      itemBuilder: (_, __) => _ShimmerCard(aspectRatio: aspectRatio),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
    );
  }
}

class ShimmerList extends StatelessWidget {
  final int itemCount;
  const ShimmerList({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) => _ShimmerTile(),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  final double aspectRatio;
  const _ShimmerCard({this.aspectRatio = 0.68});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.kSurfaceVariantDark,
      highlightColor: AppTheme.kSurfaceDark,
      child: Card(
        color: AppTheme.kSurfaceVariantDark,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(color: AppTheme.kSurfaceDark),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                height: 12,
                color: AppTheme.kSurfaceDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.kSurfaceVariantDark,
      highlightColor: AppTheme.kSurfaceDark,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.kSurfaceDark,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, color: AppTheme.kSurfaceDark),
                  const SizedBox(height: 8),
                  Container(height: 12, width: 120, color: AppTheme.kSurfaceDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ShimmerChapterTile extends StatelessWidget {
  const ShimmerChapterTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.kSurfaceVariantDark,
      highlightColor: AppTheme.kSurfaceDark,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 16,
              color: AppTheme.kSurfaceDark,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, color: AppTheme.kSurfaceDark),
                  const SizedBox(height: 6),
                  Container(width: 80, height: 11, color: AppTheme.kSurfaceDark),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppTheme.kSurfaceDark,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
