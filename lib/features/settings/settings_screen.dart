import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme/tokens.dart';
import '../../widgets/max_width_box.dart';
import 'pages/about_page.dart';
import 'pages/backup_restore_page.dart';
import 'pages/download_settings_page.dart';
import 'pages/general_settings_page.dart';
import 'pages/log_viewer_page.dart';
import 'pages/provider_management_page.dart';
import 'pages/reader_settings_page.dart';
import 'pages/theme_settings_page.dart';
import 'pages/translation_settings_page.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = 'v${info.version}');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    if (!isDesktop) return _buildMobile(context);
    return _buildDesktop(context);
  }

  // ═══════════════════════════════════════════════════════════
  // Desktop: two-pane (category list + page)
  // ═══════════════════════════════════════════════════════════

  static const _pages = <Widget>[
    GeneralSettingsPage(),
    ProviderManagementPage(),
    ReaderSettingsPage(),
    TranslationSettingsPage(),
    DownloadSettingsPage(),
    ThemeSettingsPage(),
    BackupRestorePage(),
    LogViewerPage(),
    AboutPage(),
  ];

  static const _tiles = <({IconData icon, String title, String subtitle})>[
    (
      icon: Icons.tune,
      title: 'General',
      subtitle: 'Startup tab, display defaults',
    ),
    (
      icon: Icons.language,
      title: 'Providers',
      subtitle: 'Registries and providers',
    ),
    (
      icon: Icons.text_fields,
      title: 'Reader & TTS',
      subtitle: 'Font, scroll mode, voices',
    ),
    (
      icon: Icons.translate,
      title: 'Translation',
      subtitle: 'Language and cache',
    ),
    (
      icon: Icons.download,
      title: 'Downloads',
      subtitle: 'Download queue settings',
    ),
    (icon: Icons.palette, title: 'Theme', subtitle: 'Colors and appearance'),
    (
      icon: Icons.backup,
      title: 'Backup & Restore',
      subtitle: 'Export or import data',
    ),
    (
      icon: Icons.bug_report,
      title: 'Log Viewer',
      subtitle: 'In-app debug logs',
    ),
    (
      icon: Icons.info_outline,
      title: 'About',
      subtitle: 'Version and licenses',
    ),
  ];

  Widget _buildDesktop(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: scheme.surfaceContainerLow,
            child: Container(
              width: 240,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: scheme.outlineVariant, width: 1),
                ),
              ),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.lg,
                      Insets.md,
                      Insets.lg,
                      Insets.sm,
                    ),
                    child: Text(
                      'Settings',
                      style: textTheme.titleLarge?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  for (var i = 0; i < _tiles.length; i++)
                    ListTile(
                      dense: true,
                      selected: i == _selectedIndex,
                      selectedTileColor: scheme.primaryContainer.withValues(
                        alpha: 0.35,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.sm.x),
                      ),
                      leading: Icon(
                        _tiles[i].icon,
                        size: 20,
                        color: i == _selectedIndex
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      title: Text(
                        _tiles[i].title,
                        style: TextStyle(
                          fontSize: textTheme.bodyMedium?.fontSize,
                          fontWeight: i == _selectedIndex
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: i == _selectedIndex
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      subtitle: Text(
                        _tiles[i].subtitle,
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                      onTap: () => setState(() => _selectedIndex = i),
                    ),
                  const Divider(
                    height: 24,
                    indent: Insets.lg,
                    endIndent: Insets.lg,
                  ),
                  ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.downloading,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    title: Text(
                      'Download queue',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                    subtitle: Text(
                      'Active downloads',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                    onTap: () => context.push('/downloads'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: MaxWidthBox(
              padding: EdgeInsets.zero,
              child: IndexedStack(index: _selectedIndex, children: _pages),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Mobile: section list that pushes pages
  // ═══════════════════════════════════════════════════════════

  Widget _buildMobile(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _buildSection(context, 'General', [
            _SettingsTile(
              icon: Icons.tune,
              title: 'General',
              subtitle: 'Startup tab, display defaults, app behavior',
              onTap: () => context.push('/settings/general'),
            ),
            const Divider(height: 0.5, indent: 16, endIndent: 16),
            _SettingsTile(
              icon: Icons.language,
              title: 'Providers',
              subtitle: 'Manage registries and enable/disable providers',
              onTap: () => context.push('/settings/providers'),
            ),
            const Divider(height: 0.5, indent: 16, endIndent: 16),
            _SettingsTile(
              icon: Icons.download,
              title: 'Downloads',
              subtitle: 'Download queue, settings, and storage',
              onTap: () => context.push('/downloads'),
            ),
          ]),
          const SizedBox(height: 8),
          _buildSection(context, 'Reader', [
            _SettingsTile(
              icon: Icons.text_fields,
              title: 'Reader & TTS',
              subtitle: 'Font, size, scroll mode, TTS engine & voice',
              onTap: () => context.push('/settings/reader'),
            ),
          ]),
          const SizedBox(height: 8),
          _buildSection(context, 'Appearance', [
            _SettingsTile(
              icon: Icons.palette,
              title: 'Theme',
              subtitle: 'Colors and appearance',
              onTap: () => context.push('/settings/theme'),
            ),
          ]),
          const SizedBox(height: 8),
          _buildSection(context, 'Data', [
            _SettingsTile(
              icon: Icons.backup,
              title: 'Backup & Restore',
              subtitle: 'Export or import library data',
              onTap: () => context.push('/settings/backup'),
            ),
            const Divider(height: 0.5, indent: 16, endIndent: 16),
            _SettingsTile(
              icon: Icons.translate,
              title: 'Translation',
              subtitle: 'Translation language and cache',
              onTap: () => context.push('/settings/translation'),
            ),
          ]),
          const SizedBox(height: 8),
          _buildSection(context, 'About', [
            _SettingsTile(
              icon: Icons.bug_report,
              title: 'Log Viewer',
              subtitle: 'View in-app debug logs',
              onTap: () => context.push('/settings/logs'),
            ),
            const Divider(height: 0.5, indent: 16, endIndent: 16),
            _SettingsTile(
              icon: Icons.info_outline,
              title: 'About',
              subtitle: _version.isEmpty
                  ? 'Version and licenses'
                  : 'Version and licenses ($_version)',
              onTap: () => context.push('/settings/about'),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
