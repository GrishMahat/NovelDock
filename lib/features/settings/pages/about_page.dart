import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';


class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 32),
          // App icon
          Center(
            child: SvgPicture.asset(
              'assets/images/logo.svg',
              width: 96,
              height: 96,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'NovelDock',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '1.0.0';
              return Center(
                child: Text(
                  'Version $version',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),

          _buildSection(context, 'Links'),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source Code'),
            subtitle: const Text('GitHub'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _launchUrl('https://github.com/GrishMahat/NovelDock'),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Report Issue'),
            subtitle: const Text('Found a bug? Let us know'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () =>
                _launchUrl('https://github.com/GrishMahat/NovelDock/issues'),
          ),

          const SizedBox(height: 16),
          _buildSection(context, 'Credits'),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NovelDock',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Multi-platform novel reader and downloader. '
                    'Supports reading from various novel websites via a plugin system.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'QuickNovel',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Inspired by QuickNovel by LagradOst and contributors. '
                    'NovelDock is an independent Flutter implementation with '
                    'its own architecture. Credit goes to the QuickNovel team '
                    'for the original concept.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          _buildSection(context, 'License'),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Copyright (C) 2026 Grish Mahat. '
                'This program is free software: you can redistribute it and/or '
                'modify it under the terms of the GNU General Public License '
                'version 3 or later. This software is provided as-is, without '
                'warranty of any kind. Content accessed through this app belongs '
                'to the respective content providers.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
