import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../config/app_config.dart';
import '../utils/logger.dart';
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

@DriftDatabase(
  tables: [
    Novels,
    Chapters,
    Library,
    ReadingHistory,
    DownloadsQueue,
    Bookmarks,
    Settings,
    ProviderCache,
    NovelProgress,
  ],
  daos: [
    NovelDao,
    ChapterDao,
    LibraryDao,
    HistoryDao,
    DownloadDao,
    BookmarkDao,
    SettingsDao,
    ProviderCacheDao,
    NovelProgressDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Test/in-memory constructor (does not touch the platform DB path).
  AppDatabase.withExecutor(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Add new columns to Chapters table if they don't exist.
        // Best-effort with loud logging: a failed legacy step must never
        // silently half-migrate, but it also must not brick the database.
        for (final step in <String, Future<void> Function()>{
          'addColumn chapters.ttsRead': () =>
              m.addColumn(chapters, chapters.ttsRead),
          'addColumn chapters.bookmarked': () =>
              m.addColumn(chapters, chapters.bookmarked),
          'createTable novelProgress': () => m.createTable(novelProgress),
        }.entries) {
          try {
            await step.value();
          } catch (e) {
            Log.e('DB', 'Migration v1->v2 step failed: ${step.key}', e);
          }
        }
      }
      if (from < 3) {
        // v3: hot-path indices + single-row settings invariant.
        // The Settings primary key only takes effect on fresh installs
        // (SQLite cannot add a PK to an existing table), so upgraded
        // databases get the equivalent guarantee explicitly: dedupe first,
        // then a UNIQUE index on key.
        try {
          await m.database.customStatement(
            'DELETE FROM settings WHERE rowid NOT IN '
            '(SELECT MAX(rowid) FROM settings GROUP BY "key")',
          );
          await m.database.customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS settings_key_unique '
            'ON settings ("key")',
          );
        } catch (e) {
          Log.e('DB', 'Migration v3 step failed: settings key invariant', e);
        }
        for (final indexSql in <String>[
          'CREATE INDEX IF NOT EXISTS reading_history_novel '
              'ON reading_history (novel_id, read_at)',
          'CREATE INDEX IF NOT EXISTS reading_history_chapter '
              'ON reading_history (chapter_id)',
          'CREATE INDEX IF NOT EXISTS downloads_queue_status '
              'ON downloads_queue (status)',
          'CREATE INDEX IF NOT EXISTS downloads_queue_novel_chapter '
              'ON downloads_queue (novel_id, chapter_id)',
          'CREATE INDEX IF NOT EXISTS bookmarks_novel_chapter '
              'ON bookmarks (novel_id, chapter_id)',
          'CREATE INDEX IF NOT EXISTS chapters_novel_downloaded '
              'ON chapters (novel_id, downloaded)',
          'CREATE INDEX IF NOT EXISTS chapters_novel_read '
              'ON chapters (novel_id, "read")',
        ]) {
          try {
            await m.database.customStatement(indexSql);
          } catch (e) {
            Log.e('DB', 'Migration v3 step failed: $indexSql', e);
          }
        }
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
