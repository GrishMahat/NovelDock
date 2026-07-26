import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'widgets/tts_mini_player.dart';

class NovelBaseApp extends ConsumerWidget {
  const NovelBaseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'NovelBase',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
    );
  }
}

/// Main shell with bottom navigation bar.
/// 4 tabs: [Library] [Browse] [History] [Settings]
class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  static const _tabPaths = [
    '/library',
    '/browse',
    '/history',
    '/settings',
  ];

  void _onTap(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      context.go(_tabPaths[index]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;

    return Scaffold(
      body: isDesktop
          ? CallbackShortcuts(
              bindings: {
                SingleActivator(LogicalKeyboardKey.digit1): () => _onTap(0),
                SingleActivator(LogicalKeyboardKey.digit2): () => _onTap(1),
                SingleActivator(LogicalKeyboardKey.digit3): () => _onTap(2),
                SingleActivator(LogicalKeyboardKey.digit4): () => _onTap(3),
              },
              child: Focus(
                autofocus: true,
                child: Column(
                  children: [
                    const TtsMiniPlayer(),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            )
          : Column(
        children: [
          const TtsMiniPlayer(),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTap,
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
}
