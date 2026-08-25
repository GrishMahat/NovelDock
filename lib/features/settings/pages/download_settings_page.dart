import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../../../theme/tokens.dart';
import '../../../core/utils/logger.dart';

const _tag = 'DownloadSettings';

class DownloadSettings {
  final String downloadPath;
  final bool wifiOnly;
  final int parallelDownloads;
  final bool autoDeleteRead;

  const DownloadSettings({
    this.downloadPath = '',
    this.wifiOnly = false,
    this.parallelDownloads = 3,
    this.autoDeleteRead = false,
  });

  DownloadSettings copyWith({
    String? downloadPath,
    bool? wifiOnly,
    int? parallelDownloads,
    bool? autoDeleteRead,
  }) {
    return DownloadSettings(
      downloadPath: downloadPath ?? this.downloadPath,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      parallelDownloads: parallelDownloads ?? this.parallelDownloads,
      autoDeleteRead: autoDeleteRead ?? this.autoDeleteRead,
    );
  }
}

class DownloadSettingsNotifier extends StateNotifier<DownloadSettings> {
  DownloadSettingsNotifier() : super(const DownloadSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final appDir = await getApplicationDocumentsDirectory();
      state = DownloadSettings(
        downloadPath:
            p.getString('download_path') ?? '${appDir.path}/downloads',
        wifiOnly: p.getBool('download_wifi_only') ?? false,
        parallelDownloads: p.getInt('download_parallel') ?? 3,
        autoDeleteRead: p.getBool('download_auto_delete') ?? false,
      );
    } catch (e) {
      Log.e(_tag, 'Failed to load download settings', e);
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('download_path', state.downloadPath);
      await p.setBool('download_wifi_only', state.wifiOnly);
      await p.setInt('download_parallel', state.parallelDownloads);
      await p.setBool('download_auto_delete', state.autoDeleteRead);
    } catch (e) {
      Log.e(_tag, 'Failed to save download settings', e);
    }
  }

  void _update(DownloadSettings Function(DownloadSettings) updater) {
    state = updater(state);
    _save();
  }

  void updateDownloadPath(String v) =>
      _update((s) => s.copyWith(downloadPath: v));
  void toggleWifiOnly() => _update((s) => s.copyWith(wifiOnly: !s.wifiOnly));
  void updateParallelDownloads(int v) =>
      _update((s) => s.copyWith(parallelDownloads: v));
  void toggleAutoDeleteRead() =>
      _update((s) => s.copyWith(autoDeleteRead: !s.autoDeleteRead));
}

final downloadSettingsProvider =
    StateNotifierProvider<DownloadSettingsNotifier, DownloadSettings>((ref) {
      return DownloadSettingsNotifier();
    });

class DownloadSettingsPage extends ConsumerWidget {
  const DownloadSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(downloadSettingsProvider);
    final notifier = ref.read(downloadSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Download Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(context, 'Storage'),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Download Path'),
            subtitle: Text(
              settings.downloadPath,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              // On Linux, show path in a dialog since file_picker doesn't support directory picking well
              final controller = TextEditingController(
                text: settings.downloadPath,
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
                      onPressed: () => Navigator.pop(ctx, controller.text),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );
              if (result != null && result.isNotEmpty) {
                notifier.updateDownloadPath(result);
              }
            },
          ),
          const SizedBox(height: 16),
          _section(context, 'Behavior'),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Wi-Fi Only'),
            subtitle: const Text('Only download on Wi-Fi connection'),
            value: settings.wifiOnly,
            onChanged: (_) => notifier.toggleWifiOnly(),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-delete Read'),
            subtitle: const Text('Remove downloaded chapters after reading'),
            value: settings.autoDeleteRead,
            onChanged: (_) => notifier.toggleAutoDeleteRead(),
          ),
          const SizedBox(height: 16),
          _section(context, 'Parallel Downloads'),
          _parallelDropdown(settings.parallelDownloads, notifier),
          const SizedBox(height: 16),
          _section(context, 'Queue'),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/downloads'),
              icon: const Icon(Icons.queue, size: 18),
              label: const Text('View Download Queue'),
            ),
          ),
          const SizedBox(height: 24),
          _section(context, 'Storage Info'),
          _StorageInfoCard(downloadPath: settings.downloadPath),
        ],
      ),
    );
  }

  Widget _parallelDropdown(int current, DownloadSettingsNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(
            width: 80,
            child: Text('Parallel'),
          ),
          Expanded(
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 5, label: Text('5')),
              ],
              selected: {current},
              onSelectionChanged: (s) =>
                  notifier.updateParallelDownloads(s.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _StorageInfoCard extends StatefulWidget {
  final String downloadPath;
  const _StorageInfoCard({required this.downloadPath});

  @override
  State<_StorageInfoCard> createState() => _StorageInfoCardState();
}

class _StorageInfoCardState extends State<_StorageInfoCard> {
  int _fileCount = 0;
  int _totalSize = 0;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final dir = Directory(widget.downloadPath);
      if (!await dir.exists()) {
        if (mounted) {
          setState(() {
            _fileCount = 0;
            _totalSize = 0;
          });
        }
        return;
      }

      int count = 0;
      int size = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          count++;
          size += await entity.length();
        }
      }
      if (mounted) {
        setState(() {
          _fileCount = count;
          _totalSize = size;
        });
      }
    } catch (e) {
      Log.e(_tag, 'Failed to load storage info', e);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.downloadPath,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$_fileCount files · ${_formatSize(_totalSize)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  // Refresh
                  await _loadInfo();
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
