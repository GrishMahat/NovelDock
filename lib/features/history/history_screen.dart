import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/text_utils.dart';
import '../../theme/app_theme.dart';

const _tag = 'History';

/// History screen — shows reading history timeline.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final historyDao = ref.watch(historyDaoProvider);
    final novelDao = ref.watch(novelDaoProvider);

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
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search history...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _searchQuery = ''),
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.kSurfaceVariantDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.kPrimary, width: 1),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // History list
          Expanded(
            child: StreamBuilder<List<ReadingHistoryData>>(
              stream: historyDao.watchAllHistory(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var entries = snapshot.data ?? [];
                Log.d(_tag, 'History entries: ${entries.length}');

                // Deduplicate — keep only latest per novel+chapter
                final seen = <String, ReadingHistoryData>{};
                for (final entry in entries) {
                  final key = '${entry.novelId}_${entry.chapterId}';
                  if (!seen.containsKey(key) ||
                      entry.readAt > seen[key]!.readAt) {
                    seen[key] = entry;
                  }
                }
                entries = seen.values.toList()
                  ..sort((a, b) => b.readAt.compareTo(a.readAt));

                // Filter by search
                if (_searchQuery.isNotEmpty) {
                  entries = entries.where((e) =>
                      e.novelId.toString().contains(_searchQuery) ||
                      e.chapterId.toString().contains(_searchQuery)).toList();
                }

                if (entries.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 64,
                            color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.5)),
                        const SizedBox(height: 16),
                        const Text('No reading history',
                            style: TextStyle(fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text(
                          'Start reading novels to build\nyour history.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppTheme.kTextSecondaryDark, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                // Group by date
                final grouped = _groupByDate(entries);

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _countItems(grouped),
                  itemBuilder: (context, index) =>
                      _buildItem(grouped, index, novelDao, historyDao),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<ReadingHistoryData>> _groupByDate(
      List<ReadingHistoryData> entries) {
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
      Map<String, List<ReadingHistoryData>> grouped, int index,
      NovelDao novelDao, HistoryDao historyDao) {
    int current = 0;
    for (final group in grouped.entries) {
      if (current == index) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            group.key,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.kTextSecondaryDark,
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

  void _deleteEntry(BuildContext context, WidgetRef ref,
      HistoryDao historyDao, ReadingHistoryData entry) {
    historyDao.deleteHistoryEntry(entry.id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History entry removed')),
    );
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Remove all reading history? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(historyDaoProvider).clearHistory();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('History cleared')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

/// History list tile — loads novel + chapter info from DB
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
        final title = novel?.title != null ? stripHtml(novel!.title) : 'Novel #${entry.novelId}';

        return FutureBuilder<Chapter?>(
          future: chapterDao.getChapterById(entry.chapterId),
          builder: (context, chapterSnapshot) {
            final chapter = chapterSnapshot.data;
            final chapterName = chapter?.name ?? 'Chapter #${entry.chapterId}';
            final time = DateTime.fromMillisecondsSinceEpoch(entry.readAt)
                .toLocal()
                .toString()
                .split(' ')[1]
                .substring(0, 5);
            final date = DateTime.fromMillisecondsSinceEpoch(entry.readAt)
                .toLocal()
                .toString()
                .split(' ')[0];

            return ListTile(
              leading: novel?.coverUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        novel!.coverUrl!,
                        width: 40,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 40,
                          height: 56,
                          color: AppTheme.kSurfaceVariantDark,
                          child: const Icon(Icons.book, size: 20),
                        ),
                      ),
                    )
                  : Container(
                      width: 40,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.kSurfaceVariantDark,
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
              onTap: () => context.push('/reader/${entry.novelId}/${entry.chapterId}'),
            );
          },
        );
      },
    );
  }
}
