import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../config/app_config.dart';
import 'tables.dart';
import 'daos/novel_dao.dart';
import 'daos/chapter_dao.dart';
import 'daos/library_dao.dart';
import 'daos/history_dao.dart';
import 'daos/download_dao.dart';
import 'daos/bookmark_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/provider_cache_dao.dart';
import 'daos/novel_progress_dao.dart';

export 'tables.dart';
export 'daos/novel_dao.dart';
export 'daos/chapter_dao.dart';
export 'daos/library_dao.dart';
export 'daos/history_dao.dart';
export 'daos/download_dao.dart';
export 'daos/bookmark_dao.dart';
export 'daos/settings_dao.dart';
export 'daos/provider_cache_dao.dart';
export 'daos/novel_progress_dao.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Novels,
  Chapters,
  Library,
  ReadingHistory,
  DownloadsQueue,
  Bookmarks,
  Settings,
  ProviderCache,
  NovelProgress,
], daos: [
  NovelDao,
  ChapterDao,
  LibraryDao,
  HistoryDao,
  DownloadDao,
  BookmarkDao,
  SettingsDao,
  ProviderCacheDao,
  NovelProgressDao,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Add new columns to Chapters table if they don't exist
            try {
              await m.addColumn(chapters, chapters.ttsRead);
            } catch (_) {}
            try {
              await m.addColumn(chapters, chapters.bookmarked);
            } catch (_) {}
            // Create NovelProgress table
            try {
              await m.createTable(novelProgress);
            } catch (_) {}
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final config = await AppConfig.getInstance();
    final file = File(config.databasePath);
    return NativeDatabase(file);
  });
}
