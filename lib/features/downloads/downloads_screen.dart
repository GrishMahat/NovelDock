import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../theme/app_theme.dart';
import 'providers/download_provider.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadDao = ref.watch(downloadDaoProvider);
    final downloadProgress = ref.watch(downloadProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          StreamBuilder<List<DownloadsQueueData>>(
            stream: downloadDao.watchAllDownloads(),
            builder: (context, snapshot) {
              final downloads = snapshot.data ?? [];
              if (downloads.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'Clear completed',
                onPressed: () async {
                  await downloadDao.clearCompletedDownloads();
                },
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<DownloadsQueueData>>(
        stream: downloadDao.watchAllDownloads(),
        builder: (context, snapshot) {
          final downloads = snapshot.data ?? [];

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (downloads.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.download,
                    size: 64,
                    color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text('No downloads yet', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text(
                    'Download novels from their detail page.',
                    style: TextStyle(color: AppTheme.kTextSecondaryDark),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: downloads.length,
            itemBuilder: (context, index) {
              final download = downloads[index];
              return _DownloadTile(download: download);
            },
          );
        },
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
              leading: _buildStatusIcon(download.status),
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
                  if (download.status == 'downloading' && download.progress != null)
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
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing: download.status == 'queued' || download.status == 'downloading'
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () async {
                        await ref.read(downloadDaoProvider).removeDownload(download.id);
                      },
                    )
                  : download.status == 'failed'
                      ? IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: () async {
                            await ref.read(downloadDaoProvider).updateDownloadStatus(
                              download.id,
                              'queued',
                              progress: 0,
                              error: null,
                            );
                          },
                        )
                      : null,
            );
          },
        );
      },
    );
  }

  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'downloading':
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case 'done':
        return const Icon(Icons.check_circle, color: Colors.green, size: 24);
      case 'failed':
        return const Icon(Icons.error, color: Colors.red, size: 24);
      case 'queued':
      default:
        return const Icon(Icons.schedule, color: AppTheme.kTextSecondaryDark, size: 24);
    }
  }
}
