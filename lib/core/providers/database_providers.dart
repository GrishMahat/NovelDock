import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../utils/logger.dart';

part 'database_providers.g.dart';

const _tag = 'DB';

/// Database instance provider
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  Log.i(_tag, 'Creating AppDatabase...');
  final db = AppDatabase();
  ref.onDispose(() {
    Log.i(_tag, 'Disposing AppDatabase');
    db.close();
  });
  Log.ok(_tag, 'AppDatabase created');
  return db;
}

/// DAO providers
@Riverpod(keepAlive: true)
NovelDao novelDao(Ref ref) {
  return NovelDao(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
ChapterDao chapterDao(Ref ref) {
  return ChapterDao(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
LibraryDao libraryDao(Ref ref) {
  return LibraryDao(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
HistoryDao historyDao(Ref ref) {
  return HistoryDao(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
DownloadDao downloadDao(Ref ref) {
  return DownloadDao(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
BookmarkDao bookmarkDao(Ref ref) {
  return BookmarkDao(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
SettingsDao settingsDao(Ref ref) {
  return SettingsDao(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
ProviderCacheDao providerCacheDao(Ref ref) {
  return ProviderCacheDao(ref.watch(appDatabaseProvider));
}

@Riverpod(keepAlive: true)
NovelProgressDao novelProgressDao(Ref ref) {
  return NovelProgressDao(ref.watch(appDatabaseProvider));
}
