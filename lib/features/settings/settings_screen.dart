import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _buildSection(context, 'General', [
            _SettingsTile(
              icon: Icons.language,
              title: 'Providers',
              subtitle: 'Manage registries and enable/disable providers',
              onTap: () => context.push('/settings/providers'),
            ),
            _SettingsTile(
              icon: Icons.download,
              title: 'Downloads',
              subtitle: 'Download queue, settings, and storage',
              onTap: () => context.push('/downloads'),
            ),
          ]),
          _buildSection(context, 'Reader', [
            _SettingsTile(
              icon: Icons.text_fields,
              title: 'Reader & TTS',
              subtitle: 'Font, size, scroll mode, TTS engine & voice',
              onTap: () => context.push('/settings/reader'),
            ),
          ]),
          _buildSection(context, 'Appearance', [
            _SettingsTile(
              icon: Icons.palette,
              title: 'Theme',
              subtitle: 'Colors and appearance',
              onTap: () => context.push('/settings/theme'),
            ),
          ]),
          _buildSection(context, 'Data', [
            _SettingsTile(
              icon: Icons.backup,
              title: 'Backup & Restore',
              subtitle: 'Export or import library data',
              onTap: () => context.push('/settings/backup'),
            ),
            _SettingsTile(
              icon: Icons.translate,
              title: 'Translation',
              subtitle: 'Translation language and cache',
              onTap: () => context.push('/settings/translation'),
            ),
          ]),
          _buildSection(context, 'About', [
            _SettingsTile(
              icon: Icons.bug_report,
              title: 'Log Viewer',
              subtitle: 'View in-app debug logs',
              onTap: () => context.push('/settings/logs'),
            ),
            _SettingsTile(
              icon: Icons.info_outline,
              title: 'About',
              subtitle: 'Version and licenses',
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
        ...children,
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
      leading: Icon(icon, color: AppTheme.kTextSecondaryDark),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
