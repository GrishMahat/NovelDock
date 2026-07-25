import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/app_theme.dart';

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
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.kPrimary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.book, size: 48, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'QuickNovel',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                  style: const TextStyle(color: AppTheme.kTextSecondaryDark),
                ),
              );
            },
          ),
          const SizedBox(height: 32),

          _buildSection('Links'),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Source Code'),
            subtitle: const Text('GitHub'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _launchUrl('https://github.com/user/QuickNovel'),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text('Report Issue'),
            subtitle: const Text('Found a bug? Let us know'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _launchUrl('https://github.com/user/QuickNovel/issues'),
          ),

          const SizedBox(height: 16),
          _buildSection('Credits'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('QuickNovel', style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text(
                    'Multi-platform novel reader and downloader. '
                    'Supports reading from various novel websites via a plugin system.',
                    style: TextStyle(fontSize: 13, color: AppTheme.kTextSecondaryDark),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          _buildSection('License'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'This software is provided as-is, without warranty of any kind. '
                'Use at your own risk. Content accessed through this app belongs to '
                'the respective content providers.',
                style: TextStyle(fontSize: 12, color: AppTheme.kTextSecondaryDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.kPrimary),
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
