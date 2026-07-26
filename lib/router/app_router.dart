import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../features/import/import_screen.dart';
import '../main.dart' show sharedFilePath;

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/library',
    routes: [
      // Shell route wraps the 4 bottom nav tabs
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
            pageBuilder: (context, state) => const NoTransitionPage(
              child: BrowseScreen(),
            ),
          ),
          GoRoute(
            path: '/history',
            name: 'history',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HistoryScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),

      // Non-tab routes (no bottom nav)
      GoRoute(
        path: '/search/results',
        name: 'searchResults',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => SearchResultsScreen(
          query: state.uri.queryParameters['q'] ?? '',
        ),
      ),
      GoRoute(
        path: '/provider/:id',
        name: 'provider',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ProviderScreen(
          providerId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: '/novel/:id',
        name: 'novelDetail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => NovelDetailScreen(
          novelId: int.parse(state.pathParameters['id'] ?? '0'),
        ),
      ),
      GoRoute(
        path: '/reader/:novelId/:chapterId',
        name: 'reader',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ReaderScreen(
          novelId: int.parse(state.pathParameters['novelId'] ?? '0'),
          chapterId: int.parse(state.pathParameters['chapterId'] ?? '0'),
        ),
      ),
      GoRoute(
        path: '/downloads',
        name: 'downloads',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DownloadsScreen(),
      ),
      GoRoute(
        path: '/settings/providers',
        name: 'providerManagement',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProviderManagementPage(),
      ),
      GoRoute(
        path: '/settings/reader',
        name: 'readerSettings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ReaderSettingsPage(),
      ),
      GoRoute(
        path: '/settings/translation',
        name: 'translationSettings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const TranslationSettingsPage(),
      ),
      GoRoute(
        path: '/settings/downloads',
        name: 'downloadSettings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DownloadSettingsPage(),
      ),
      GoRoute(
        path: '/settings/about',
        name: 'about',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const AboutPage(),
      ),
      GoRoute(
        path: '/import',
        name: 'import',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ImportScreen(
          initialFilePath: state.uri.queryParameters['file'] ?? sharedFilePath,
        ),
      ),
    ],
  );
});
