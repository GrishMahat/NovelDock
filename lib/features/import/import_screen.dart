import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';

class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.file_upload,
              size: 64,
              color: AppTheme.kTextSecondaryDark.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text('Import EPUB or PDF', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              'Select a file from your device\nto add to your library.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.kTextSecondaryDark),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                // TODO: file_picker
              },
              icon: const Icon(Icons.file_open),
              label: const Text('Choose File'),
            ),
          ],
        ),
      ),
    );
  }
}
