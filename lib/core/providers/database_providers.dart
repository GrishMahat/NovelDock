import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../utils/logger.dart';

const _tag = 'DB';

/// Database instance provider
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  Log.i(_tag, 'Creating AppDatabase...');
  final db = AppDatabase();
  ref.onDispose(() {
    Log.i(_tag, 'Disposing AppDatabase');
    db.close();
  });
  Log.ok(_tag, 'AppDatabase created');
  return db;
});

/// DAO providers
final novelDaoProvider = Provider<NovelDao>((ref) {
  return NovelDao(ref.watch(appDatabaseProvider));
});

final chapterDaoProvider = Provider<ChapterDao>((ref) {
  return ChapterDao(ref.watch(appDatabaseProvider));
});

final libraryDaoProvider = Provider<LibraryDao>((ref) {
  return LibraryDao(ref.watch(appDatabaseProvider));
});

final historyDaoProvider = Provider<HistoryDao>((ref) {
  return HistoryDao(ref.watch(appDatabaseProvider));
});

final downloadDaoProvider = Provider<DownloadDao>((ref) {
  return DownloadDao(ref.watch(appDatabaseProvider));
});

final bookmarkDaoProvider = Provider<BookmarkDao>((ref) {
  return BookmarkDao(ref.watch(appDatabaseProvider));
});

final settingsDaoProvider = Provider<SettingsDao>((ref) {
  return SettingsDao(ref.watch(appDatabaseProvider));
});

final providerCacheDaoProvider = Provider<ProviderCacheDao>((ref) {
  return ProviderCacheDao(ref.watch(appDatabaseProvider));
});

final novelProgressDaoProvider = Provider<NovelProgressDao>((ref) {
  return NovelProgressDao(ref.watch(appDatabaseProvider));
});
