import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/logger.dart';
import '../../../theme/app_theme.dart';

const _tag = 'GeneralSettings';

class GeneralSettings {
  final int startupTab;
  final String defaultDisplayMode;
  final bool confirmExit;
  final bool showNsfw;

  const GeneralSettings({
    this.startupTab = 0,
    this.defaultDisplayMode = 'grid',
    this.confirmExit = false,
    this.showNsfw = false,
  });

  GeneralSettings copyWith({
    int? startupTab,
    String? defaultDisplayMode,
    bool? confirmExit,
    bool? showNsfw,
  }) {
    return GeneralSettings(
      startupTab: startupTab ?? this.startupTab,
      defaultDisplayMode: defaultDisplayMode ?? this.defaultDisplayMode,
      confirmExit: confirmExit ?? this.confirmExit,
      showNsfw: showNsfw ?? this.showNsfw,
    );
  }
}

final generalSettingsProvider =
    StateNotifierProvider<GeneralSettingsNotifier, GeneralSettings>((ref) {
      return GeneralSettingsNotifier();
    });

class GeneralSettingsNotifier extends StateNotifier<GeneralSettings> {
  GeneralSettingsNotifier() : super(const GeneralSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = GeneralSettings(
        startupTab: p.getInt('startup_tab') ?? 0,
        defaultDisplayMode: p.getString('default_display_mode') ?? 'grid',
        confirmExit: p.getBool('confirm_exit') ?? false,
        showNsfw: p.getBool('show_nsfw') ?? false,
      );
    } catch (e) {
      Log.e(_tag, 'Failed to load general settings', e);
    }
  }

  Future<void> setStartupTab(int tab) async {
    state = state.copyWith(startupTab: tab);
    final p = await SharedPreferences.getInstance();
    await p.setInt('startup_tab', tab);
  }

  Future<void> setDefaultDisplayMode(String mode) async {
    state = state.copyWith(defaultDisplayMode: mode);
    final p = await SharedPreferences.getInstance();
    await p.setString('default_display_mode', mode);
  }

  Future<void> setConfirmExit(bool value) async {
    state = state.copyWith(confirmExit: value);
    final p = await SharedPreferences.getInstance();
    await p.setBool('confirm_exit', value);
  }

  Future<void> setShowNsfw(bool value) async {
    state = state.copyWith(showNsfw: value);
    final p = await SharedPreferences.getInstance();
    await p.setBool('show_nsfw', value);
  }
}

class GeneralSettingsPage extends ConsumerWidget {
  const GeneralSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(generalSettingsProvider);
    final notifier = ref.read(generalSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('General Settings')),
      body: ListView(
        children: [
          _buildSection('Startup Tab'),
          RadioGroup<int>(
            groupValue: settings.startupTab,
            onChanged: (v) {
              if (v != null) notifier.setStartupTab(v);
            },
            child: Column(
              children: [
                RadioListTile<int>(title: const Text('Library'), value: 0),
                RadioListTile<int>(title: const Text('Browse'), value: 1),
                RadioListTile<int>(title: const Text('History'), value: 2),
              ],
            ),
          ),
          const Divider(),
          _buildSection('Library Default View'),
          RadioGroup<String>(
            groupValue: settings.defaultDisplayMode,
            onChanged: (v) {
              if (v != null) notifier.setDefaultDisplayMode(v);
            },
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('Grid View'),
                  value: 'grid',
                ),
                RadioListTile<String>(
                  title: const Text('List View'),
                  value: 'list',
                ),
                RadioListTile<String>(
                  title: const Text('Compact View'),
                  value: 'compact',
                ),
              ],
            ),
          ),
          const Divider(),
          _buildSection('Application Behavior'),
          SwitchListTile(
            title: const Text('Confirm before exit'),
            subtitle: const Text('Prompt for confirmation before closing app'),
            value: settings.confirmExit,
            onChanged: (v) => notifier.setConfirmExit(v),
          ),
          SwitchListTile(
            title: const Text('Show NSFW Sources'),
            subtitle: const Text('Display 18+ provider extensions in Browse'),
            value: settings.showNsfw,
            onChanged: (v) async {
              if (v) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Age Verification'),
                    content: const Text(
                      'NSFW content may contain adult material. Are you 18 or older?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('I am 18+'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  notifier.setShowNsfw(true);
                }
              } else {
                notifier.setShowNsfw(false);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.kPrimary,
        ),
      ),
    );
  }
}
