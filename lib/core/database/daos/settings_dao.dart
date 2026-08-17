import 'package:drift/drift.dart';

import '../database.dart';
import '../tables.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [Settings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(AppDatabase db) : super(db);

  Future<void> setSetting(String key, String value) async {
    await (delete(settings)..where((t) => t.key.equals(key))).go();
    await into(settings).insert(
      SettingsCompanion(
        key: Value(key),
        value: Value(value),
      ),
    );
  }

  Future<String?> getSetting(String key) async {
    final results = await (select(settings)
          ..where((t) => t.key.equals(key)))
        .get();
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
