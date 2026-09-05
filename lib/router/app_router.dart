import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app.dart';
import '../features/search/search_results_screen.dart';
import '../features/browse/browse_screen.dart';
import '../features/browse/provider_screen.dart';
import '../features/novel/novel_detail_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/library/library_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/history/history_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/pages/provider_management_page.dart';
import '../features/settings/pages/reader_settings_page.dart';
import '../features/settings/pages/translation_settings_page.dart';
import '../features/settings/pages/download_settings_page.dart';
import '../features/settings/pages/about_page.dart';
import '../features/settings/pages/theme_settings_page.dart';
import '../features/settings/pages/backup_restore_page.dart';
import '../features/settings/pages/log_viewer_page.dart';
import '../features/settings/pages/general_settings_page.dart';
import '../features/import/import_screen.dart';
import '../main.dart' show sharedFilePath;
import '../core/config/app_prefs.dart';

part 'app_router.g.dart';

/// Shell-tab locations indexed by the "Startup tab" general setting.
const _tabLocations = ['/library', '/browse', '/history'];

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>();

/// Routes nested under the shell (rail/top bar visible on desktop) are listed
/// first; routes that must stay full-screen (e.g. the immersive reader) sit at
/// the root navigator level.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final startupTab = ref.watch(appPrefsProvider).getInt('startup_tab') ?? 0;
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation:
        _tabLocations[startupTab.clamp(0, _tabLocations.length - 1)],
    routes: [
      // Shell route wraps the 4 tabs AND every sub-page so the desktop rail +
      // top bar stay visible while navigating. On mobile, MainShell hides the
      // bottom nav for sub-pages, preserving the previous full-screen feel.
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return MainShell(child: child);
        },
        routes: [
          GoRoute(
            path: '/library',
            name: 'library',
            builder: (context, state) => const LibraryScreen(),
          ),
          GoRoute(
            path: '/browse',
            name: 'browse',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: BrowseScreen()),
          ),
          GoRoute(
            path: '/history',
            name: 'history',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HistoryScreen()),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
          GoRoute(
            path: '/search/results',
            name: 'searchResults',
            builder: (context, state) => SearchResultsScreen(
              query: state.uri.queryParameters['q'] ?? '',
            ),
          ),
          GoRoute(
            path: '/provider/:id',
            name: 'provider',
            builder: (context, state) =>
                ProviderScreen(providerId: state.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: '/novel/:id',
            name: 'novelDetail',
            builder: (context, state) => NovelDetailScreen(
              novelId: int.parse(state.pathParameters['id'] ?? '0'),
            ),
          ),
          GoRoute(
            path: '/downloads',
            name: 'downloads',
            builder: (context, state) => const DownloadsScreen(),
          ),
          GoRoute(
            path: '/settings/providers',
            name: 'providerManagement',
            builder: (context, state) => const ProviderManagementPage(),
          ),
          GoRoute(
            path: '/settings/reader',
            name: 'readerSettings',
            builder: (context, state) => const ReaderSettingsPage(),
          ),
          GoRoute(
            path: '/settings/translation',
            name: 'translationSettings',
            builder: (context, state) => const TranslationSettingsPage(),
          ),
          GoRoute(
            path: '/settings/downloads',
            name: 'downloadSettings',
            builder: (context, state) => const DownloadSettingsPage(),
          ),
          GoRoute(
            path: '/settings/about',
            name: 'about',
            builder: (context, state) => const AboutPage(),
          ),
          GoRoute(
            path: '/settings/theme',
            name: 'themeSettings',
            builder: (context, state) => const ThemeSettingsPage(),
          ),
          GoRoute(
            path: '/settings/backup',
            name: 'backupRestore',
            builder: (context, state) => const BackupRestorePage(),
          ),
          GoRoute(
            path: '/settings/logs',
            name: 'logViewer',
            builder: (context, state) => const LogViewerPage(),
          ),
          GoRoute(
            path: '/settings/general',
            name: 'generalSettings',
            builder: (context, state) => const GeneralSettingsPage(),
          ),
          GoRoute(
            path: '/import',
            name: 'import',
            builder: (context, state) => ImportScreen(
              initialFilePath:
                  state.uri.queryParameters['file'] ?? sharedFilePath,
            ),
          ),
        ],
      ),

      // Full-screen immersive routes (no shell chrome)
      GoRoute(
        path: '/reader/:novelId/:chapterId',
        name: 'reader',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ReaderScreen(
          novelId: int.parse(state.pathParameters['novelId'] ?? '0'),
          chapterId: int.parse(state.pathParameters['chapterId'] ?? '0'),
        ),
      ),
    ],
  );
}
