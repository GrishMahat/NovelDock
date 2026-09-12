import 'package:drift/drift.dart';

import '../database.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  /// Single atomic upsert: the primary key on [Settings.key] (plus the
  /// unique index created by the v3 migration on pre-existing databases)
  /// makes duplicates impossible, so no delete + insert dance is needed.
  Future<void> setSetting(String key, String value) {
    return into(settings).insert(
      SettingsCompanion(key: Value(key), value: Value(value)),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<String?> getSetting(String key) async {
    final results = await (select(
      settings,
    )..where((t) => t.key.equals(key))).get();
    if (results.isEmpty) return null;
    return results.first.value;
  }

  Future<String> getSettingOrDefault(String key, String defaultValue) async {
    return await getSetting(key) ?? defaultValue;
  }

  Future<void> deleteSetting(String key) async {
    await (delete(settings)..where((t) => t.key.equals(key))).go();
  }

  Future<Map<String, String>> getAllSettings() async {
    final all = await select(settings).get();
    return {for (final s in all) s.key: s.value};
  }

  Stream<Map<String, String>> watchAllSettings() {
    return select(settings).watch().map((entries) {
      return {for (final s in entries) s.key: s.value};
    });
  }
}
