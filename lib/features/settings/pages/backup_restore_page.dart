import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/utils/logger.dart';
import '../../../theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;

const _tag = 'Backup';

class BackupRestorePage extends ConsumerWidget {
  const BackupRestorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup, color: AppTheme.kPrimary),
                  title: const Text('Export Library'),
                  subtitle: const Text(
                    'Save your library and settings as a JSON file',
                  ),
                  onTap: () => _exportBackup(context, ref),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.restore, color: AppTheme.kPrimary),
                  title: const Text('Import Library'),
                  subtitle: const Text(
                    'Restore from a previously exported backup',
                  ),
                  onTap: () => _importBackup(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'What gets exported:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _bullet('Novels in your library'),
                  _bullet('Reading history'),
                  _bullet('Bookmarks'),
                  _bullet('Download queue state'),
                  _bullet('App settings'),
                  _bullet('Provider cache info'),
                  const SizedBox(height: 12),
                  Text(
                    'Provider JS files themselves are not included. '
                    'They will be re-downloaded from registries on restore.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.check, size: 16, color: AppTheme.kPrimary),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    try {
      final novelDao = ref.read(novelDaoProvider);
      final historyDao = ref.read(historyDaoProvider);
      final bookmarkDao = ref.read(bookmarkDaoProvider);
      final downloadDao = ref.read(downloadDaoProvider);
      final settingsDao = ref.read(settingsDaoProvider);
      final providerCacheDao = ref.read(providerCacheDaoProvider);

      final novels = await novelDao.getAllNovels();
      final allHistory = await historyDao.getAllHistory();
      final allBookmarks = await bookmarkDao.getAllBookmarks();
      final downloadEntries = await downloadDao.getAllDownloads();
      final settingsMap = await settingsDao.getAllSettings();
      final providerCache = await providerCacheDao.getAllProviders();

      final backup = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'novels': novels
            .map(
              (n) => {
                'id': n.id,
                'providerId': n.providerId,
                'url': n.url,
                'title': n.title,
                'author': n.author,
                'coverUrl': n.coverUrl,
                'description': n.description,
                'genres': n.genres,
                'status': n.status,
                'addedAt': n.addedAt,
              },
            )
            .toList(),
        'history': allHistory
            .map(
              (h) => {
                'novelId': h.novelId,
                'chapterId': h.chapterId,
                'readAt': h.readAt,
                'scrollPosition': h.scrollPosition,
                'progress': h.progress,
              },
            )
            .toList(),
        'bookmarks': allBookmarks
            .map(
              (b) => {
                'novelId': b.novelId,
                'chapterId': b.chapterId,
                'position': b.position,
                'note': b.note,
                'createdAt': b.createdAt,
              },
            )
            .toList(),
        'downloads': downloadEntries
            .map(
              (d) => {
                'novelId': d.novelId,
                'chapterId': d.chapterId,
                'status': d.status,
                'progress': d.progress,
                'error': d.error,
              },
            )
            .toList(),
        'settings': settingsMap,
        'providerCache': providerCache
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'version': p.version,
                'enabled': p.enabled,
                'lastUpdated': p.lastUpdated,
              },
            )
            .toList(),
      };

      final jsonStr = const JsonEncoder.withIndent('  ').convert(backup);

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/noveldock_backup_$timestamp.json');
      await file.writeAsString(jsonStr);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'NovelDock Backup'),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup exported successfully')),
        );
      }

      Log.ok(_tag, 'Backup exported: ${file.path}');
    } catch (e) {
      Log.e(_tag, 'Export failed', e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result.isEmpty) return;

      final file = File(result.single.path!);
      final jsonStr = await file.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (data['version'] != 1) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unsupported backup version')),
          );
        }
        return;
      }

      final novelDao = ref.read(novelDaoProvider);
      final historyDao = ref.read(historyDaoProvider);
      final bookmarkDao = ref.read(bookmarkDaoProvider);
      final settingsDao = ref.read(settingsDaoProvider);

      int imported = 0;

      final novelsList = data['novels'] as List? ?? [];
      for (final n in novelsList) {
        try {
          await novelDao.insertOrGetNovel(
            providerId: n['providerId'] as String? ?? '',
            url: n['url'] as String? ?? '',
            title: n['title'] as String? ?? '',
            author: n['author'] as String?,
            coverUrl: n['coverUrl'] as String?,
          );
          imported++;
        } catch (e) {
          Log.w(_tag, 'Failed to import novel: $e');
        }
      }

      final historyList = data['history'] as List? ?? [];
      for (final h in historyList) {
        try {
          await historyDao.addHistoryEntry(
            ReadingHistoryCompanion(
              novelId: Value(h['novelId'] as int),
              chapterId: Value(h['chapterId'] as int),
              readAt: Value(
                h['readAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
              ),
              scrollPosition: Value(h['scrollPosition'] as double?),
            ),
          );
        } catch (e) {
          Log.w(_tag, 'Failed to import history: $e');
        }
      }

      final bookmarkList = data['bookmarks'] as List? ?? [];
      for (final b in bookmarkList) {
        try {
          await bookmarkDao.addBookmark(
            BookmarksCompanion(
              novelId: Value(b['novelId'] as int),
              chapterId: Value(b['chapterId'] as int),
              position: Value(b['position'] as String? ?? '0'),
              note: b['note'] != null
                  ? Value(b['note'] as String)
                  : const Value.absent(),
              createdAt: Value(
                b['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
              ),
            ),
          );
        } catch (e) {
          Log.w(_tag, 'Failed to import bookmark: $e');
        }
      }

      final settingsMap = data['settings'] as Map<String, dynamic>? ?? {};
      for (final entry in settingsMap.entries) {
        try {
          await settingsDao.setSetting(entry.key, entry.value.toString());
        } catch (e) {
          Log.w(_tag, 'Failed to import setting: $e');
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import complete: $imported novels restored')),
        );
      }

      Log.ok(_tag, 'Backup imported: $imported novels');
    } catch (e) {
      Log.e(_tag, 'Import failed', e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }
}
