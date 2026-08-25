import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/utils/platform.dart';
import 'features/settings/pages/theme_settings_page.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
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
      darkTheme: isAmoled
          ? AppTheme.amoled(primary: accentColor)
          : AppTheme.dark(primary: accentColor),
      themeMode: themeMode,
    );
  }
}

/// Main shell. Desktop: NavigationRail + top bar. Mobile: bottom navigation bar.
/// 4 tabs: [Library] [Browse] [History] [Settings]
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabPaths = ['/library', '/browse', '/history', '/settings'];

  /// Derive the active tab index from the current GoRouter location so the
  /// rail/bar stays in sync even after deep-link/notification navigation.
  int _indexFromLocation(String location) {
    for (int i = _tabPaths.length - 1; i >= 0; i--) {
      if (location.startsWith(_tabPaths[i])) return i;
    }
    return 0;
  }

  /// Whether [location] is one of the four top-level tabs (vs a nested
  /// sub-page like /provider/:id or /search/results).
  bool _isTabLocation(String location) => _tabPaths.any(location.startsWith);

  void _onTap(BuildContext context, int index) {
    context.go(_tabPaths[index]);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexFromLocation(location);

    final shell = Column(
      children: [
        const TtsMiniPlayer(),
        Expanded(child: child),
      ],
    );

    // Status bar icons must contrast with the app theme, not the system
    // setting; without this, dark mode + light system skin = invisible icons.
    final overlayStyle = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    final annotatedShell = AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: shell,
    );

    final bindings = <ShortcutActivator, VoidCallback>{
      // Tab switching
      const SingleActivator(LogicalKeyboardKey.digit1): () =>
          _onTap(context, 0),
      const SingleActivator(LogicalKeyboardKey.digit2): () =>
          _onTap(context, 1),
      const SingleActivator(LogicalKeyboardKey.digit3): () =>
          _onTap(context, 2),
      const SingleActivator(LogicalKeyboardKey.digit4): () =>
          _onTap(context, 3),
      // Navigation shortcuts
      const SingleActivator(LogicalKeyboardKey.keyD, control: true): () =>
          context.push('/downloads'),
      const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
          _onTap(context, 3),
      // Refresh shortcut — invalidate provider on current tab via F5 or Ctrl+R
      const SingleActivator(LogicalKeyboardKey.f5): () =>
          _requestRefresh(context, currentIndex),
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): () =>
          _requestRefresh(context, currentIndex),
    };

    if (isDesktop) {
      return Scaffold(
        body: CallbackShortcuts(
          bindings: bindings,
          child: Focus(
            autofocus: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DesktopRail(
                  currentIndex: currentIndex,
                  onSelect: (i) => _onTap(context, i),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const TtsMiniPlayer(),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: annotatedShell,
      bottomNavigationBar: _isTabLocation(location)
          ? NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (i) => _onTap(context, i),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.library_books_outlined),
                  selectedIcon: Icon(Icons.library_books),
                  label: 'Library',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore),
                  label: 'Browse',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.history),
                  selectedIcon: Icon(Icons.history),
                  label: 'History',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            )
          : null,
    );
  }

  /// Sends a refresh notification to the currently visible tab.
  /// Each tab screen listens for this via a [_RefreshNotification].
  void _requestRefresh(BuildContext context, int tabIndex) {
    _RefreshNotification(tabIndex).dispatch(context);
  }
}

/// Desktop rail: main tabs pinned at the top, Settings pinned at the bottom.
class _DesktopRail extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const _DesktopRail({required this.currentIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: Desktop.railWidth,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: Insets.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _RailButton(
                  icon: Icons.library_books_outlined,
                  selectedIcon: Icons.library_books,
                  label: 'Library',
                  tooltip: 'Library (1)',
                  selected: currentIndex == 0,
                  onTap: () => onSelect(0),
                ),
                _RailButton(
                  icon: Icons.explore_outlined,
                  selectedIcon: Icons.explore,
                  label: 'Browse',
                  tooltip: 'Browse (2)',
                  selected: currentIndex == 1,
                  onTap: () => onSelect(1),
                ),
                _RailButton(
                  icon: Icons.history,
                  selectedIcon: Icons.history,
                  label: 'History',
                  tooltip: 'History (3)',
                  selected: currentIndex == 2,
                  onTap: () => onSelect(2),
                ),
              ],
            ),
          ),
          Divider(
            indent: Insets.lg,
            endIndent: Insets.lg,
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          _RailButton(
            icon: Icons.download_outlined,
            selectedIcon: Icons.download,
            label: 'Downloads',
            tooltip: 'Downloads (Ctrl+D)',
            selected: false,
            onTap: () => context.push('/downloads'),
          ),
          _RailButton(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: 'Settings',
            tooltip: 'Settings (Ctrl+,)',
            selected: currentIndex == 3,
            onTap: () => onSelect(3),
          ),
          const SizedBox(height: Insets.sm),
        ],
      ),
    );
  }
}

/// One rail destination: 64x36 indicator pill + 12px label.
class _RailButton extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Insets.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: Motion.fast,
                curve: Curves.easeOut,
                width: 64,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  selected ? selectedIcon : icon,
                  size: 26,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Insets.xs),
              Text(
                label,
                style: text.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notification dispatched when the user hits F5 / Ctrl+R.
class _RefreshNotification extends Notification {
  final int tabIndex;
  const _RefreshNotification(this.tabIndex);
}
