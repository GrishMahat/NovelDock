import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:epubx_kuebiko/epubx_kuebiko.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

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
  final String? initialFilePath;
  const ImportScreen({super.key, this.initialFilePath});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _isImporting = false;
  String? _importedFile;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _importFromPath(widget.initialFilePath!);
      });
    }
  }

  Future<void> _importFromPath(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      setState(() { _error = 'File not found: $path'; });
      return;
    }
    setState(() { _isImporting = true; _error = null; });

    try {
      final fileName = p.basename(path);
      final ext = p.extension(fileName).toLowerCase();

      Log.i(_tag, 'Importing from share intent: $fileName ($ext)');

      final config = await AppConfig.getInstance();
      final importDir = Directory(p.join(config.dataDir.path, 'imports'));
      await importDir.create(recursive: true);
      final destPath = p.join(importDir.path, fileName);
      await file.copy(destPath);
      Log.ok(_tag, 'Copied to: $destPath');

      final novelDao = ref.read(novelDaoProvider);
      final novelId = await novelDao.insertNovel(NovelsCompanion(
        providerId: const Value('local'),
        url: Value(destPath),
        title: Value(p.basenameWithoutExtension(fileName)),
        addedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ));

      final libraryDao = ref.read(libraryDaoProvider);
      await libraryDao.addToLibrary(novelId);
      Log.ok(_tag, 'Added to library: novelId=$novelId');

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

    if (result.isEmpty) return;
    final file = result.first;
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

      // Extract cover image
      String? coverUrl;
      if (book.CoverImage != null) {
        try {
          final config = await AppConfig.getInstance();
          final coversDir = Directory(p.join(config.dataDir.path, 'covers'));
          await coversDir.create(recursive: true);
          final coverPath = p.join(coversDir.path, '$novelId.jpg');
          final jpegBytes = img.encodeJpg(img.copyResize(book.CoverImage!, width: 300));
          await File(coverPath).writeAsBytes(jpegBytes);
          coverUrl = coverPath;
          Log.ok(_tag, 'Saved EPUB cover: $coverPath');
        } catch (e) {
          Log.e(_tag, 'Failed to save EPUB cover', e);
        }
      }

      // Update novel metadata
      final db = ref.read(appDatabaseProvider);
      await (db.update(db.novels)..where((t) => t.id.equals(novelId))).write(
        NovelsCompanion(
          title: Value(book.Title ?? p.basenameWithoutExtension(filePath)),
          author: Value(book.Author),
          coverUrl: coverUrl != null ? Value(coverUrl) : const Value.absent(),
        ),
      );

      // Add chapters
      final chapterDao = ref.read(chapterDaoProvider);
      // Delete existing chapters before re-inserting to prevent duplicates
      await chapterDao.deleteChaptersForNovel(novelId);
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
      // Store PDF as single chapter — rendered by pdfrx in reader
      final chapterDao = ref.read(chapterDaoProvider);
      await chapterDao.insertChapter(ChaptersCompanion(
        novelId: Value(novelId),
        name: Value('PDF Document'),
        url: Value('pdf://$filePath#page=1'),
        index: Value(0),
      ));
      Log.ok(_tag, 'Added PDF as single chapter');
    } catch (e) {
      Log.e(_tag, 'PDF parse failed', e);
    }
  }
}
