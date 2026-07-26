import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/app_theme.dart';
import '../../../core/utils/logger.dart';

const _tag = 'ThemeSettings';

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, String>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<String> {
  ThemeModeNotifier() : super('system') { _load(); }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = p.getString('theme_mode') ?? 'system';
    } catch (e) {
      Log.e(_tag, 'Failed to load theme mode', e);
    }
  }

  Future<void> setMode(String mode) async {
    state = mode;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('theme_mode', mode);
    } catch (e) {
      Log.e(_tag, 'Failed to save theme mode', e);
    }
  }
}

final accentColorProvider = StateNotifierProvider<AccentColorNotifier, int>((ref) {
  return AccentColorNotifier();
});

class AccentColorNotifier extends StateNotifier<int> {
  AccentColorNotifier() : super(AppTheme.kPrimary.toARGB32()) { _load(); }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = p.getInt('accent_color') ?? AppTheme.kPrimary.toARGB32();
    } catch (e) {
      Log.e(_tag, 'Failed to load accent color', e);
    }
  }

  Future<void> setColor(int color) async {
    state = color;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('accent_color', color);
    } catch (e) {
      Log.e(_tag, 'Failed to save accent color', e);
    }
  }
}

class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  static const _themeModes = [
    ('system', 'Follow System', Icons.settings_suggest),
    ('light', 'Light', Icons.light_mode),
    ('dark', 'Dark', Icons.dark_mode),
    ('amoled', 'AMOLED', Icons.contrast),
  ];

  static const _accentColors = [
    ('Default Blue', Color(0xFF356AE6)),
    ('Purple', Color(0xFF7C4DFF)),
    ('Green', Color(0xFF4CAF50)),
    ('Red', Color(0xFFE53935)),
    ('Orange', Color(0xFFFF9800)),
    ('Pink', Color(0xFFE91E63)),
    ('Teal', Color(0xFF009688)),
    ('Indigo', Color(0xFF3F51B5)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeModeProvider);
    final currentColor = ref.watch(accentColorProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: ListView(
        children: [
          _buildSection('Theme Mode'),
          ..._themeModes.map((mode) => ListTile(
            leading: Icon(mode.$3, color: AppTheme.kTextSecondaryDark),
            title: Text(mode.$2),
            trailing: Radio<String>(
              value: mode.$1,
              groupValue: currentMode,
              onChanged: (v) {
                if (v != null) ref.read(themeModeProvider.notifier).setMode(v);
              },
            ),
            onTap: () => ref.read(themeModeProvider.notifier).setMode(mode.$1),
          )),
          _buildSection('Accent Color'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _accentColors.map((c) {
                final isSelected = currentColor == c.$2.toARGB32();
                return GestureDetector(
                  onTap: () => ref.read(accentColorProvider.notifier).setColor(c.$2.toARGB32()),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: c.$2,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: isSelected
                          ? [BoxShadow(color: c.$2.withValues(alpha: 0.5), blurRadius: 8)]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.kPrimary),
      ),
    );
  }
}
