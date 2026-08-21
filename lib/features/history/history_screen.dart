import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/platform.dart';
import '../../core/utils/text_utils.dart';
import '../../theme/tokens.dart';
import '../../widgets/header_search_field.dart';
import '../../widgets/max_width_box.dart';
import '../../widgets/page_header.dart';
import '../../widgets/shimmer_list.dart';

const _tag = 'History';

/// History screen, showing the reading history timeline.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _searchQuery = '';
  late final Future<List<Novel>> _novelsFuture = ref
      .read(novelDaoProvider)
      .getAllNovels();

  @override
  Widget build(BuildContext context) {
    final historyDao = ref.watch(historyDaoProvider);
    final novelDao = ref.watch(novelDaoProvider);

    final historyList = FutureBuilder<List<Novel>>(
      future: _novelsFuture,
      builder: (context, novelsSnap) {
        final novelsById = {
          for (final n in novelsSnap.data ?? const <Novel>[]) n.id: n,
        };
        return StreamBuilder<List<ReadingHistoryData>>(
          stream: historyDao.watchAllHistory(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ShimmerList();
            }

            var entries = snapshot.data ?? [];
            Log.d(_tag, 'History entries: ${entries.length}');

            // Ensure exactly one entry per novel (latest read)
            final seen = <int, ReadingHistoryData>{};
            for (final entry in entries) {
              if (!seen.containsKey(entry.novelId) ||
                  entry.readAt > seen[entry.novelId]!.readAt) {
                seen[entry.novelId] = entry;
              }
            }
            entries = seen.values.toList()
              ..sort((a, b) => b.readAt.compareTo(a.readAt));

            // Filter by novel title / author
            final query = _searchQuery.trim().toLowerCase();
            if (query.isNotEmpty) {
              entries = entries.where((entry) {
                final novel = novelsById[entry.novelId];
                if (novel == null) return false;
                final title = stripHtml(novel.title).toLowerCase();
                final author = novel.author?.toLowerCase() ?? '';
                return title.contains(query) || author.contains(query);
              }).toList();
            }

            if (entries.isEmpty) {
              final filtered = query.isNotEmpty;
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history,
                      size: 64,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: Insets.lg),
                    Text(
                      filtered
                          ? 'No results for "$_searchQuery"'
                          : 'No reading history',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Insets.sm),
                    Text(
                      filtered
                          ? 'Try a different title or author.'
                          : 'Start reading novels to build\nyour history.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            // Group by date
            final grouped = _groupByDate(entries);

            return MaxWidthBox(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: _countItems(grouped),
                itemBuilder: (context, index) =>
                    _buildItem(grouped, index, novelDao, historyDao),
              ),
            );
          },
        );
      },
    );

    if (isDesktop) {
      return Scaffold(
        body: Column(
          children: [
            PageHeader(
              title: 'History',
              search: HeaderSearchField(
                hint: 'Filter history',
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              actions: [
                Tooltip(
                  message: 'Clear all history',
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmClearAll(context, ref),
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Clear all'),
                  ),
                ),
              ],
            ),
            Expanded(child: historyList),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _searchQuery.isNotEmpty
            ? Text('History: $_searchQuery')
            : const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _confirmClearAll(context, ref),
            tooltip: 'Clear all history',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.sm,
              Insets.lg,
              Insets.sm,
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Filter history...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(child: historyList),
        ],
      ),
    );
  }

  Map<String, List<ReadingHistoryData>> _groupByDate(
    List<ReadingHistoryData> entries,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final grouped = <String, List<ReadingHistoryData>>{};

    for (final entry in entries) {
      final date = DateTime.fromMillisecondsSinceEpoch(entry.readAt);
      final dateOnly = DateTime(date.year, date.month, date.day);

      String group;
      if (dateOnly.isAtSameMomentAs(today)) {
        group = 'Today';
      } else if (dateOnly.isAtSameMomentAs(yesterday)) {
        group = 'Yesterday';
      } else if (dateOnly.isAfter(weekAgo)) {
        group = 'This Week';
      } else {
        group = 'Earlier';
      }

      grouped.putIfAbsent(group, () => []).add(entry);
    }

    return grouped;
  }

  int _countItems(Map<String, List<ReadingHistoryData>> grouped) {
    int count = 0;
    for (final entry in grouped.entries) {
      count += 1 + entry.value.length;
    }
    return count;
  }

  Widget _buildItem(
    Map<String, List<ReadingHistoryData>> grouped,
    int index,
    NovelDao novelDao,
    HistoryDao historyDao,
  ) {
    int current = 0;
    for (final group in grouped.entries) {
      if (current == index) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.lg,
            Insets.lg,
            Insets.sm,
          ),
          child: Text(
            group.key,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }
      current++;
      for (final entry in group.value) {
        if (current == index) {
          return _HistoryTile(
            entry: entry,
            novelDao: novelDao,
            onDelete: () => _deleteEntry(context, ref, historyDao, entry),
          );
        }
        current++;
      }
    }
    return const SizedBox.shrink();
  }

  void _deleteEntry(
    BuildContext context,
    WidgetRef ref,
    HistoryDao historyDao,
    ReadingHistoryData entry,
  ) {
    historyDao.deleteHistoryEntry(entry.id);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('History entry removed')));
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'Remove all reading history? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(historyDaoProvider).clearHistory();
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('History cleared')));
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

/// History list tile. Loads novel + chapter info from DB.
class _HistoryTile extends ConsumerWidget {
  final ReadingHistoryData entry;
  final NovelDao novelDao;
  final VoidCallback onDelete;

  const _HistoryTile({
    required this.entry,
    required this.novelDao,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapterDao = ref.read(chapterDaoProvider);
    return FutureBuilder<Novel?>(
      future: novelDao.getNovelById(entry.novelId),
      builder: (context, novelSnapshot) {
        final novel = novelSnapshot.data;
        final title = novel?.title != null
            ? stripHtml(novel!.title)
            : 'Novel #${entry.novelId}';

        return FutureBuilder<Chapter?>(
          future: chapterDao.getChapterById(entry.chapterId),
          builder: (context, chapterSnapshot) {
            final chapter = chapterSnapshot.data;
            final chapterName = chapter?.name ?? 'Chapter #${entry.chapterId}';
            final time = DateTime.fromMillisecondsSinceEpoch(
              entry.readAt,
            ).toLocal().toString().split(' ')[1].substring(0, 5);
            final date = DateTime.fromMillisecondsSinceEpoch(
              entry.readAt,
            ).toLocal().toString().split(' ')[0];

            return ListTile(
              leading: novel?.coverUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        novel!.coverUrl!,
                        width: 40,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 40,
                          height: 56,
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.book, size: 20),
                        ),
                      ),
                    )
                  : Container(
                      width: 40,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.book, size: 20),
                    ),
              title: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: Text(
                '$chapterName · $date $time',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
              ),
              onTap: () =>
                  context.push('/reader/${entry.novelId}/${entry.chapterId}'),
            );
          },
        );
      },
    );
  }
}
