import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../theme/app_theme.dart';

/// History screen — shows reading history timeline.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _isGrid = false;

  @override
  Widget build(BuildContext context) {
    final historyDao = ref.watch(historyDaoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view),
            onPressed: () => setState(() => _isGrid = !_isGrid),
          ),
        ],
      ),
      body: StreamBuilder<List<ReadingHistoryData>>(
        stream: historyDao.watchAllHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data ?? [];

          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No reading history',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Start reading novels to build\nyour history.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.kTextSecondaryDark,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }

          // Group by date
          final grouped = _groupByDate(entries);

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _countItems(grouped),
            itemBuilder: (context, index) {
              return _buildItem(grouped, index);
            },
          );
        },
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
      final date =
          DateTime.fromMillisecondsSinceEpoch(entry.readAt);
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
      count += 1 + entry.value.length; // header + items
    }
    return count;
  }

  Widget _buildItem(Map<String, List<ReadingHistoryData>> grouped, int index) {
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
          return ListTile(
            leading: Container(
              width: 48,
              height: 48,
              color: AppTheme.kSurfaceVariantDark,
              child: const Icon(Icons.book, size: 24),
            ),
            title: Text('Novel #${entry.novelId}'),
            subtitle: Text(
              'Chapter #${entry.chapterId}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Text(
              DateTime.fromMillisecondsSinceEpoch(entry.readAt)
                  .toLocal()
                  .toString()
                  .split(' ')[1]
                  .substring(0, 5),
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () => context.push('/reader/${entry.novelId}/${entry.chapterId}'),
          );
        }
        current++;
      }
    }
    return const SizedBox.shrink();
  }
}
