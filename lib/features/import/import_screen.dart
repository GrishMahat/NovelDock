import 'dart:io';

import 'package:drift/drift.dart' show Value, InsertMode;
import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/config/app_config.dart';
import '../../core/database/database.dart';
import '../../core/providers/database_providers.dart';
import '../../core/utils/logger.dart';
import '../../theme/app_theme.dart';

const _tag = 'Import';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _isImporting = false;
  String? _importedFile;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: Center(
        child: _isImporting
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Importing...'),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.file_upload, size: 64,
                      color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  const Text('Import EPUB or PDF',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text('Select a file from your device\nto add to your library.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.kTextSecondaryDark)),
                  if (_importedFile != null) ...[
                    const SizedBox(height: 16),
                    Card(child: ListTile(
                      leading: const Icon(Icons.check_circle, color: Colors.green),
                      title: Text('Imported: $_importedFile'),
                      subtitle: const Text('Added to library'),
                    )),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Card(child: ListTile(
                      leading: const Icon(Icons.error, color: Colors.red),
                      title: Text('Error: $_error'),
                    )),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _isImporting ? null : _pickFile,
                    icon: const Icon(Icons.file_open),
                    label: const Text('Choose File'),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf'],
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    setState(() { _isImporting = true; _error = null; });

    try {
      final sourceFile = File(file.path!);
      final fileName = p.basename(file.path!);
      final ext = p.extension(fileName).toLowerCase();

      Log.i(_tag, 'Importing: $fileName ($ext)');

      // Copy to app storage
      final config = await AppConfig.getInstance();
      final importDir = Directory(p.join(config.dataDir.path, 'imports'));
      await importDir.create(recursive: true);
      final destPath = p.join(importDir.path, fileName);
      await sourceFile.copy(destPath);
      Log.ok(_tag, 'Copied to: $destPath');

      // Add to database
      final novelDao = ref.read(novelDaoProvider);
      final novelId = await novelDao.insertNovel(NovelsCompanion(
        providerId: const Value('local'),
        url: Value(destPath),
        title: Value(p.basenameWithoutExtension(fileName)),
        addedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      // Also add to library so it appears in Library tab
      final libraryDao = ref.read(libraryDaoProvider);
      await libraryDao.addToLibrary(novelId);

      Log.ok(_tag, 'Added to library: novelId=$novelId');

      // Parse epub chapters
      if (ext == '.epub') {
        await _parseEpub(destPath, novelId);
      } else if (ext == '.pdf') {
        await _parsePdf(destPath, novelId);
      }

      setState(() { _isImporting = false; _importedFile = fileName; });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported: $fileName')),
        );
      }
    } catch (e) {
      Log.e(_tag, 'Import failed', e);
      setState(() { _isImporting = false; _error = e.toString(); });
    }
  }

  Future<void> _parseEpub(String filePath, int novelId) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final book = await EpubReader.readBook(bytes);

      Log.i(_tag, 'EPUB: ${book.Title}, ${book.Chapters?.length ?? 0} chapters');

      // Update novel metadata (only the fields we want to change)
      final novelDao = ref.read(novelDaoProvider);
      final db = ref.read(appDatabaseProvider);
      await (db.update(db.novels)..where((t) => t.id.equals(novelId))).write(
        NovelsCompanion(
          title: Value(book.Title ?? p.basenameWithoutExtension(filePath)),
          author: Value(book.Author),
        ),
      );

      // Add chapters
      final chapterDao = ref.read(chapterDaoProvider);
      if (book.Chapters != null) {
        for (var i = 0; i < book.Chapters!.length; i++) {
          final ch = book.Chapters![i];
          await chapterDao.insertChapter(ChaptersCompanion(
            novelId: Value(novelId),
            name: Value(ch.Title ?? 'Chapter ${i + 1}'),
            url: Value('epub://$filePath#${ch.Title ?? '$i'}'),
            index: Value(i.toDouble()),
          ));
        }
        Log.ok(_tag, 'Added ${book.Chapters!.length} chapters from EPUB');
      }
    } catch (e) {
      Log.e(_tag, 'EPUB parse failed', e);
    }
  }

  Future<void> _parsePdf(String filePath, int novelId) async {
    try {
      // pdfx doesn't support Linux — store as single-chapter PDF
      final chapterDao = ref.read(chapterDaoProvider);
      await chapterDao.insertChapter(ChaptersCompanion(
        novelId: Value(novelId),
        name: Value('PDF Document'),
        url: Value('pdf://$filePath#page=1'),
        index: Value(0),
      ));
      Log.ok(_tag, 'Added PDF as single chapter (pdfx not supported on Linux)');
    } catch (e) {
      Log.e(_tag, 'PDF parse failed', e);
    }
  }
}
