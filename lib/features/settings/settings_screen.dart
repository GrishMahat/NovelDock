import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';

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

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
          child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.kPrimary)),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  const _SettingsTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
