import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';


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
      itemBuilder: (_, index) => _ShimmerCard(
        key: ValueKey('shimmer_card_$index'),
        aspectRatio: aspectRatio,
      ),
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
      itemBuilder: (context, index) =>
          _ShimmerTile(key: ValueKey('shimmer_tile_$index')),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  final double aspectRatio;
  const _ShimmerCard({super.key, this.aspectRatio = 0.68});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      highlightColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: Container(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6))),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(height: 12, color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerTile extends StatelessWidget {
  const _ShimmerTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      highlightColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 120,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
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

class ShimmerChapterTile extends StatelessWidget {
  const ShimmerChapterTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      highlightColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(width: 4, height: 16, color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)),
                  const SizedBox(height: 6),
                  Container(
                    width: 80,
                    height: 11,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
