import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download,
              size: 64,
              color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text('No downloads yet', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              'Download novels to read offline.',
              style: TextStyle(color: AppTheme.kTextSecondaryDark),
            ),
          ],
        ),
      ),
    );
  }
}
