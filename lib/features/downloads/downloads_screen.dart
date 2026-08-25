import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../core/utils/platform.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/max_width_box.dart';
import '../../widgets/shimmer_list.dart';
import '../settings/pages/download_settings_page.dart';
import 'providers/download_provider.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    // Requeue tasks stuck in 'downloading' from a killed session and drain
    // anything still queued.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(downloadProvider.notifier).resumePendingDownloads();
    });
  }

  /// Header action: re-queues every failed task when any exists.
  Widget _retryFailedAction(List<DownloadsQueueData> downloads) {
    final hasFailed = downloads.any((d) => d.status == 'failed');
    if (!hasFailed) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Retry failed',
      onPressed: () async {
        final notifier = ref.read(downloadProvider.notifier);
        for (final novelId
            in downloads
                .where((d) => d.status == 'failed')
                .map((d) => d.novelId)
                .toSet()) {
          await notifier.retryFailed(novelId);
        }
      },
    );
  }

  Widget _clearActions() {
    return StreamBuilder<List<DownloadsQueueData>>(
      stream: ref.watch(downloadDaoProvider).watchAllDownloads(),
      builder: (context, snapshot) {
        final downloads = snapshot.data ?? [];
        if (downloads.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _retryFailedAction(downloads),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear completed',
              onPressed: () async {
                await ref.read(downloadDaoProvider).clearCompletedDownloads();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloadDao = ref.watch(downloadDaoProvider);
    final dlSettings = ref.watch(downloadSettingsProvider);
    final dlNotifier = ref.read(downloadSettingsProvider.notifier);

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(title: const Text('Downloads'), actions: [_clearActions()]),
      body: Column(
        children: [
          if (isDesktop)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.md,
                Insets.lg,
                Insets.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Downloads',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  _clearActions(),
                ],
              ),
            ),
          // ── Settings toggle ──
          ExpansionTile(
            leading: const Icon(Icons.settings, size: 20),
            title: const Text(
              'Download Settings',
              style: TextStyle(fontSize: 14),
            ),
            initiallyExpanded: _showSettings,
            onExpansionChanged: (expanded) =>
                setState(() => _showSettings = expanded),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    // Path
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Path', style: TextStyle(fontSize: 13)),
                      subtitle: Text(
                        dlSettings.downloadPath,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.edit, size: 18),
                      onTap: () async {
                        final controller = TextEditingController(
                          text: dlSettings.downloadPath,
                        );
                        final result = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Download Path'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, controller.text),
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        );
                        if (result != null && result.isNotEmpty) {
                          dlNotifier.updateDownloadPath(result);
                        }
                      },
                    ),
                    // Wi-Fi only
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Wi-Fi Only',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: dlSettings.wifiOnly,
                      onChanged: (_) => dlNotifier.toggleWifiOnly(),
                    ),
                    // Parallel
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Parallel Downloads',
                        style: TextStyle(fontSize: 13),
                      ),
                      trailing: DropdownButton<int>(
                        value: dlSettings.parallelDownloads,
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1')),
                          DropdownMenuItem(value: 2, child: Text('2')),
                          DropdownMenuItem(value: 3, child: Text('3')),
                          DropdownMenuItem(value: 5, child: Text('5')),
                        ],
                        onChanged: (v) {
                          if (v != null) dlNotifier.updateParallelDownloads(v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 1),

          // ── Download queue ──
          Expanded(
            child: StreamBuilder<List<DownloadsQueueData>>(
              stream: downloadDao.watchAllDownloads(),
              builder: (context, snapshot) {
                final downloads = snapshot.data ?? [];

                // The stream is recreated on rebuilds; never blank an
                // already-loaded queue with a skeleton flash.
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const ShimmerList();
                }

                if (downloads.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.download,
                          size: 64,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No downloads yet',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Download novels from their detail page.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return MaxWidthBox(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: downloads.length,
                    itemBuilder: (context, index) =>
                        _DownloadTile(download: downloads[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  final DownloadsQueueData download;
  const _DownloadTile({required this.download});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapterDao = ref.watch(chapterDaoProvider);
    final novelDao = ref.watch(novelDaoProvider);

    return FutureBuilder<Chapter?>(
      future: chapterDao.getChapterById(download.chapterId),
      builder: (context, chapterSnapshot) {
        final chapter = chapterSnapshot.data;

        return FutureBuilder<Novel?>(
          future: novelDao.getNovelById(download.novelId),
          builder: (context, novelSnapshot) {
            final novel = novelSnapshot.data;

            return ListTile(
              leading: _buildStatusIcon(context, download.status),
              title: Text(
                chapter?.name ?? 'Chapter #${download.chapterId}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    novel?.title ?? 'Novel #${download.novelId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (download.status == 'downloading' &&
                      download.progress != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(
                        value: download.progress,
                        minHeight: 3,
                      ),
                    ),
                  if (download.status == 'failed' && download.error != null)
                    Text(
                      download.error!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing:
                  download.status == 'queued' ||
                      download.status == 'downloading'
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'Cancel',
                      onPressed: () => ref
                          .read(downloadProvider.notifier)
                          .cancelTask(download.id),
                    )
                  : download.status == 'failed'
                  ? IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: 'Retry',
                      onPressed: () => ref
                          .read(downloadProvider.notifier)
                          .retryTask(download.id),
                    )
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildStatusIcon(BuildContext context, String status) {
    switch (status) {
      case 'downloading':
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case 'done':
        return Icon(
          Icons.check_circle,
          color: Theme.of(context).extension<AppColors>()!.ongoing,
          size: 24,
        );
      case 'failed':
        return Icon(
          Icons.error,
          color: Theme.of(context).colorScheme.error,
          size: 24,
        );
      case 'queued':
      default:
        return Icon(
          Icons.schedule,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 24,
        );
    }
  }
}
