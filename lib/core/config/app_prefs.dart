import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'app_prefs.g.dart';

/// Synchronous handle to the app-wide SharedPreferences instance.
///
/// `main()` awaits the instance before `runApp` and overrides this provider
/// with it, so settings notifiers and the router read persisted values before
/// the first frame instead of flashing defaults and re-rendering.
@Riverpod(keepAlive: true)
SharedPreferences appPrefs(Ref ref) {
  throw UnimplementedError(
    'appPrefsProvider must be overridden in main() with the loaded instance',
  );
}

/// Resolved application documents directory.
///
/// Overridden in `main()` like [appPrefsProvider] so download settings can
/// compute their default path synchronously.
@Riverpod(keepAlive: true)
Directory appDocumentsDir(Ref ref) {
  throw UnimplementedError(
    'appDocumentsDirProvider must be overridden in main() with the resolved directory',
  );
}
