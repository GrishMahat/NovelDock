import 'package:drift/drift.dart';

// ─── novels ───────────────────────────────────────────────
class Novels extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get providerId => text()();
  TextColumn get url => text().unique()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get coverUrl => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get genres => text().nullable()(); // JSON array
  TextColumn get status => text().nullable()(); // Ongoing | Completed | Dropped
  IntColumn get addedAt => integer()();
}

// ─── chapters ─────────────────────────────────────────────
class Chapters extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get novelId => integer().references(Novels, #id)();
  TextColumn get name => text()();
  TextColumn get url => text()();
  RealColumn get index => real()();
  BoolColumn get downloaded => boolean().withDefault(const Constant(false))();
  BoolColumn get read => boolean().withDefault(const Constant(false))();
  BoolColumn get bookmarked => boolean().withDefault(const Constant(false))();
  TextColumn get downloadedPath => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [{novelId, url}];
}

// ─── library ──────────────────────────────────────────────
class Library extends Table {
  IntColumn get novelId => integer().references(Novels, #id)();
  IntColumn get lastChapterId => integer().references(Chapters, #id).nullable()();
  IntColumn get lastReadAt => integer().nullable()();
  IntColumn get order => integer().nullable()();
  TextColumn get status => text().nullable()(); // Reading | On Hold | Plan to Read | Completed | Dropped

  @override
  Set<Column> get primaryKey => {novelId};
}

// ─── reading_history ──────────────────────────────────────
class ReadingHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get novelId => integer().references(Novels, #id)();
  IntColumn get chapterId => integer().references(Chapters, #id)();
  IntColumn get readAt => integer()();
  RealColumn get scrollPosition => real().nullable()();
  RealColumn get progress => real().nullable()();
}

// ─── downloads_queue ──────────────────────────────────────
class DownloadsQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get novelId => integer().references(Novels, #id)();
  IntColumn get chapterId => integer().references(Chapters, #id)();
  TextColumn get status => text()(); // queued | downloading | done | failed
  RealColumn get progress => real().nullable()();
  TextColumn get error => text().nullable()();
}

// ─── bookmarks ────────────────────────────────────────────
class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get novelId => integer().references(Novels, #id)();
  IntColumn get chapterId => integer().references(Chapters, #id)();
  TextColumn get position => text().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer()();
}

// ─── settings ─────────────────────────────────────────────
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
}

// ─── provider_cache ───────────────────────────────────────
class ProviderCache extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get version => text()();
  TextColumn get jsSource => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  IntColumn get lastUpdated => integer()();
}
