import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/settings/pages/theme_settings_page.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'widgets/tts_mini_player.dart';

class NovelDockApp extends ConsumerWidget {
  const NovelDockApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeModeStr = ref.watch(themeModeProvider);
    final accentColorInt = ref.watch(accentColorProvider);

    final themeMode = switch (themeModeStr) {
      'light' => ThemeMode.light,
      'dark' || 'amoled' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final accentColor = Color(accentColorInt);
    final isAmoled = themeModeStr == 'amoled';

    return MaterialApp.router(
      title: 'NovelDock',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(primary: accentColor),
      darkTheme: isAmoled ? AppTheme.amoled(primary: accentColor) : AppTheme.dark(primary: accentColor),
      themeMode: themeMode,
    );
  }
}

/// Main shell with bottom navigation bar.
/// 4 tabs: [Library] [Browse] [History] [Settings]
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabPaths = [
    '/library',
    '/browse',
    '/history',
    '/settings',
  ];

  /// Derive the active tab index from the current GoRouter location so the
  /// bottom bar stays in sync even after deep-link/notification navigation.
  int _indexFromLocation(String location) {
    for (int i = _tabPaths.length - 1; i >= 0; i--) {
      if (location.startsWith(_tabPaths[i])) return i;
    }
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    context.go(_tabPaths[index]);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);

    final shell = Column(
      children: [
        const TtsMiniPlayer(),
        Expanded(child: child),
      ],
    );

    return Scaffold(
      body: isDesktop
          ? CallbackShortcuts(
              bindings: {
                // Tab switching
                const SingleActivator(LogicalKeyboardKey.digit1): () => _onTap(context, 0),
                const SingleActivator(LogicalKeyboardKey.digit2): () => _onTap(context, 1),
                const SingleActivator(LogicalKeyboardKey.digit3): () => _onTap(context, 2),
                const SingleActivator(LogicalKeyboardKey.digit4): () => _onTap(context, 3),
                // Navigation shortcuts
                const SingleActivator(LogicalKeyboardKey.keyD, control: true): () => context.push('/downloads'),
                const SingleActivator(LogicalKeyboardKey.comma, control: true): () => _onTap(context, 3),
                // Refresh shortcut — invalidate provider on current tab via F5 or Ctrl+R
                const SingleActivator(LogicalKeyboardKey.f5): () => _requestRefresh(context, currentIndex),
                const SingleActivator(LogicalKeyboardKey.keyR, control: true): () => _requestRefresh(context, currentIndex),
              },
              child: Focus(
                autofocus: true,
                child: shell,
              ),
            )
          : shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) => _onTap(context, i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  /// Sends a refresh notification to the currently visible tab.
  /// Each tab screen listens for this via a [_RefreshNotification].
  void _requestRefresh(BuildContext context, int tabIndex) {
    _RefreshNotification(tabIndex).dispatch(context);
  }
}

/// Notification dispatched when the user hits F5 / Ctrl+R.
class _RefreshNotification extends Notification {
  final int tabIndex;
  const _RefreshNotification(this.tabIndex);
}
