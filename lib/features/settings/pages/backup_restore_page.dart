import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_providers.dart';
import '../../../core/utils/logger.dart';
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
                  leading: Icon(
                    Icons.backup,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('Export Library'),
                  subtitle: const Text(
                    'Save your library and settings as a JSON file',
                  ),
                  onTap: () => _exportBackup(context, ref),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.restore,
                    color: Theme.of(context).colorScheme.primary,
                  ),
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
                  _bullet(context, 'Novels in your library'),
                  _bullet(context, 'Reading history'),
                  _bullet(context, 'Bookmarks'),
                  _bullet(context, 'Reader highlights and notes'),
                  _bullet(context, 'Download queue state'),
                  _bullet(context, 'App settings'),
                  _bullet(context, 'Provider cache info'),
                  const SizedBox(height: 12),
                  Text(
                    'Provider JS files themselves are not included. '
                    'They will be re-downloaded from registries on restore.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

  Widget _bullet(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.check, size: 16, color: scheme.primary),
          const SizedBox(width: Insets.sm),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    try {
      final novelDao = ref.read(novelDaoProvider);
      final chapterDao = ref.read(chapterDaoProvider);
      final historyDao = ref.read(historyDaoProvider);
      final bookmarkDao = ref.read(bookmarkDaoProvider);
      final annotationDao = ref.read(annotationDaoProvider);
      final downloadDao = ref.read(downloadDaoProvider);
      final settingsDao = ref.read(settingsDaoProvider);
      final providerCacheDao = ref.read(providerCacheDaoProvider);

      final novels = await novelDao.getAllNovels();
      final allHistory = await historyDao.getAllHistory();
      final allBookmarks = await bookmarkDao.getAllBookmarks();
      final downloadEntries = await downloadDao.getAllDownloads();
      final settingsMap = await settingsDao.getAllSettings();
      final providerCache = await providerCacheDao.getAllProviders();
      // URL-keyed rows: integer row ids are meaningless in another database,
      // so history/bookmarks/downloads carry the novel + chapter URLs needed
      // to remap them on import. Rows whose targets no longer resolve are
      // skipped there, never written dangling.
      Future<Map<String, String?>> urlsFor(int novelId, int chapterId) async {
        final novel = await novelDao.getNovelById(novelId);
        final chapter = await ref
            .read(chapterDaoProvider)
            .getChapterById(chapterId);
        return {'novelUrl': novel?.url, 'chapterUrl': chapter?.url};
      }

      final historyRows = <Map<String, dynamic>>[];
      for (final h in allHistory) {
        final urls = await urlsFor(h.novelId, h.chapterId);
        historyRows.add({
          'novelUrl': urls['novelUrl'],
          'chapterUrl': urls['chapterUrl'],
          'readAt': h.readAt,
          'scrollPosition': h.scrollPosition,
          'progress': h.progress,
        });
      }

      final bookmarkRows = <Map<String, dynamic>>[];
      for (final b in allBookmarks) {
        final urls = await urlsFor(b.novelId, b.chapterId);
        bookmarkRows.add({
          'novelUrl': urls['novelUrl'],
          'chapterUrl': urls['chapterUrl'],
          'position': b.position,
          'note': b.note,
          'createdAt': b.createdAt,
        });
      }

      final downloadRows = <Map<String, dynamic>>[];
      for (final d in downloadEntries) {
        final urls = await urlsFor(d.novelId, d.chapterId);
        downloadRows.add({
          'novelUrl': urls['novelUrl'],
          'chapterUrl': urls['chapterUrl'],
          'status': d.status,
          'progress': d.progress,
          'error': d.error,
        });
      }

      final annotationRows = <Map<String, dynamic>>[];
      for (final novel in novels) {
        final annotations = await annotationDao.getForNovel(novel.id);
        for (final a in annotations) {
          final chapter = await chapterDao.getChapterById(a.chapterId);
          annotationRows.add({
            'novelUrl': novel.url,
            'chapterUrl': chapter?.url,
            'paragraphIndex': a.paragraphIndex,
            'quote': a.quote,
            'note': a.note,
            'createdAt': a.createdAt,
          });
        }
      }

      final backup = {
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'novels': novels
            .map(
              (n) => {
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
        'history': historyRows,
        'bookmarks': bookmarkRows,
        'annotations': annotationRows,
        'downloads': downloadRows,
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

      final version = data['version'];
      if (version != 1 && version != 2) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unsupported backup version')),
          );
        }
        return;
      }
      final isV2 = version == 2;

      final novelDao = ref.read(novelDaoProvider);
      final chapterDao = ref.read(chapterDaoProvider);
      final historyDao = ref.read(historyDaoProvider);
      final bookmarkDao = ref.read(bookmarkDaoProvider);
      final annotationDao = ref.read(annotationDaoProvider);
      final downloadDao = ref.read(downloadDaoProvider);
      final settingsDao = ref.read(settingsDaoProvider);
      final db = ref.read(appDatabaseProvider);

      final settingsMap = Map<String, dynamic>.from(
        data['settings'] as Map? ?? {},
      );

      // Registries are code sources: never adopt them silently from a file
      // someone shared. List every URL and let the user decline (in which
      // case the enabled-providers selection goes with them — ids without
      // their registries resolve to nothing). Dismissal aborts the import.
      if (!context.mounted) return;
      final registryDecision = await _confirmRegistryRestore(
        context,
        settingsMap,
      );
      if (registryDecision == null) return;
      if (!registryDecision) {
        settingsMap.remove('registries');
        settingsMap.remove('enabled_providers');
        Log.i(_tag, 'Import: registry adoption declined by user');
      }

      int imported = 0;
      int skippedRows = 0;

      // One transaction: a failed import leaves no half-restored library.
      await db.transaction(() async {
        // Novel URL -> fresh row id in THIS database. Source-DB integer ids
        // are meaningless here and must never be written (dangling refs).
        final novelIdsByUrl = <String, int>{};
        final novelsList = data['novels'] as List? ?? [];
        for (final n in novelsList) {
          try {
            final map = n as Map<String, dynamic>;
            final url = map['url'] as String? ?? '';
            if (url.isEmpty) {
              skippedRows++;
              continue;
            }
            final id = await novelDao.insertOrGetNovel(
              providerId: map['providerId'] as String? ?? '',
              url: url,
              title: map['title'] as String? ?? url,
              author: map['author'] as String?,
              coverUrl: map['coverUrl'] as String?,
            );
            novelIdsByUrl[url] = id;
            imported++;
          } catch (e) {
            Log.w(_tag, 'Failed to import novel: $e');
          }
        }

        // Resolve a chapter URL within its remapped novel, if present.
        Future<int?> resolveChapter(
          String? novelUrl,
          String? chapterUrl,
        ) async {
          if (novelUrl == null || chapterUrl == null) return null;
          final novelId = novelIdsByUrl[novelUrl];
          if (novelId == null) return null;
          final chapter = await chapterDao.getChapterByNovelAndUrl(
            novelId,
            chapterUrl,
          );
          return chapter?.id;
        }

        final historyList = data['history'] as List? ?? [];
        for (final h in historyList) {
          try {
            final map = h as Map<String, dynamic>;
            final novelUrl = map['novelUrl'] as String?;
            final novelId = novelUrl == null ? null : novelIdsByUrl[novelUrl];
            final chapterId = isV2
                ? await resolveChapter(novelUrl, map['chapterUrl'] as String?)
                : null;
            if (novelId == null || chapterId == null) {
              // v1 rows carry only source-DB ints (unmappable), v2 rows
              // whose chapter was not re-fetched yet: skip, never dangle.
              skippedRows++;
              continue;
            }
            await historyDao.addHistoryEntry(
              ReadingHistoryCompanion(
                novelId: Value(novelId),
                chapterId: Value(chapterId),
                readAt: Value(
                  (map['readAt'] as num?)?.toInt() ??
                      DateTime.now().millisecondsSinceEpoch,
                ),
                scrollPosition: Value(
                  (map['scrollPosition'] as num?)?.toDouble(),
                ),
              ),
            );
          } catch (e) {
            Log.w(_tag, 'Failed to import history: $e');
          }
        }

        final bookmarkList = data['bookmarks'] as List? ?? [];
        for (final b in bookmarkList) {
          try {
            final map = b as Map<String, dynamic>;
            final novelUrl = map['novelUrl'] as String?;
            final novelId = novelUrl == null ? null : novelIdsByUrl[novelUrl];
            final chapterId = isV2
                ? await resolveChapter(novelUrl, map['chapterUrl'] as String?)
                : null;
            if (novelId == null || chapterId == null) {
              skippedRows++;
              continue;
            }
            await bookmarkDao.addBookmark(
              BookmarksCompanion(
                novelId: Value(novelId),
                chapterId: Value(chapterId),
                position: Value(map['position'] as String? ?? '0'),
                note: map['note'] != null
                    ? Value(map['note'] as String)
                    : const Value.absent(),
                createdAt: Value(
                  (map['createdAt'] as num?)?.toInt() ??
                      DateTime.now().millisecondsSinceEpoch,
                ),
              ),
            );
          } catch (e) {
            Log.w(_tag, 'Failed to import bookmark: $e');
          }
        }

        final annotationList = data['annotations'] as List? ?? [];
        for (final a in annotationList) {
          try {
            final map = a as Map<String, dynamic>;
            final novelUrl = map['novelUrl'] as String?;
            final novelId = novelUrl == null ? null : novelIdsByUrl[novelUrl];
            final chapterId = isV2
                ? await resolveChapter(novelUrl, map['chapterUrl'] as String?)
                : null;
            final quote = map['quote'] as String?;
            if (novelId == null || chapterId == null || quote == null) {
              skippedRows++;
              continue;
            }
            // Same position = same highlight: keep the import idempotent.
            final dupe = await annotationDao.getForPosition(
              novelId,
              chapterId,
              (map['paragraphIndex'] as num?)?.toInt() ?? 0,
            );
            if (dupe != null) continue;
            await annotationDao.addAnnotation(
              AnnotationsCompanion.insert(
                novelId: novelId,
                chapterId: chapterId,
                chapterUrl: map['chapterUrl'] as String? ?? '',
                paragraphIndex: (map['paragraphIndex'] as num?)?.toInt() ?? 0,
                quote: quote,
                note: Value(map['note'] as String?),
                createdAt:
                    (map['createdAt'] as num?)?.toInt() ??
                    DateTime.now().millisecondsSinceEpoch,
              ),
            );
          } catch (e) {
            Log.w(_tag, 'Failed to import annotation: $e');
          }
        }

        // Queue state: only unfinished work transfers, re-queued from
        // scratch. 'done' rows without their files would be lies that
        // reconciliation deletes on next open anyway.
        final downloadsList = data['downloads'] as List? ?? [];
        for (final d in downloadsList) {
          try {
            final map = d as Map<String, dynamic>;
            if ((map['status'] as String? ?? '') == 'done') continue;
            final novelUrl = map['novelUrl'] as String?;
            final novelId = novelUrl == null ? null : novelIdsByUrl[novelUrl];
            final chapterId = isV2
                ? await resolveChapter(novelUrl, map['chapterUrl'] as String?)
                : null;
            if (novelId == null || chapterId == null) {
              skippedRows++;
              continue;
            }
            if (await downloadDao.getQueuedDownload(novelId, chapterId) ==
                null) {
              await downloadDao.enqueueDownload(
                DownloadsQueueCompanion.insert(
                  novelId: novelId,
                  chapterId: chapterId,
                  status: 'queued',
                ),
              );
            }
          } catch (e) {
            Log.w(_tag, 'Failed to import download: $e');
          }
        }

        for (final entry in settingsMap.entries) {
          try {
            await settingsDao.setSetting(entry.key, entry.value.toString());
          } catch (e) {
            Log.w(_tag, 'Failed to import setting: $e');
          }
        }
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import complete: $imported novels restored'
              '${skippedRows > 0 ? ' ($skippedRows rows skipped: refresh those novels to re-fetch their chapters)' : ''}',
            ),
          ),
        );
      }

      Log.ok(_tag, 'Backup imported: $imported novels ($skippedRows skipped)');
    } catch (e) {
      Log.e(_tag, 'Import failed', e);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  /// Registry URLs embedded in the backup's settings, if any.
  List<String> _backupRegistryUrls(Map<String, dynamic> settingsMap) {
    try {
      final raw = settingsMap['registries'];
      if (raw == null) return const [];
      final list = (jsonDecode(raw as String) as List)
          .cast<Map<String, dynamic>>();
      return [
        for (final r in list)
          if (r['url'] is String && (r['url'] as String).isNotEmpty)
            r['url'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Ask before adopting code sources from a shared file. Returns true to
  /// restore them, false to skip them, null when dismissed without deciding
  /// (the caller aborts the import: silence must not mean consent).
  Future<bool?> _confirmRegistryRestore(
    BuildContext context,
    Map<String, dynamic> settingsMap,
  ) async {
    final urls = _backupRegistryUrls(settingsMap);
    if (urls.isEmpty || !context.mounted) return true;
    var keep = true;
    var decided = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore source registries?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This backup adds these novel-source registries. '
                'Registries run code when their providers load, so only '
                'restore ones you trust.',
              ),
              const SizedBox(height: 12),
              for (final url in urls)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    url,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              keep = false;
              decided = true;
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Skip registries'),
          ),
          FilledButton(
            onPressed: () {
              keep = true;
              decided = true;
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Restore all'),
          ),
        ],
      ),
    );
    // Back button is disabled (barrierDismissible false), but a route pop
    // from elsewhere must not silently adopt: treat undecided as abort.
    if (!decided) return null;
    return keep;
  }
}
