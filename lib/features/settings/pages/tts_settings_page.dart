import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TTSSettingsPage extends ConsumerWidget {
  const TTSSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('TTS Settings')),
      body: const Center(child: Text('TTS settings coming soon')),
    );
  }
}
