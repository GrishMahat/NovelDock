import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/tokens.dart';
import '../../../core/config/app_prefs.dart';
import '../../../core/utils/logger.dart';

part 'theme_settings_page.g.dart';

const _tag = 'ThemeSettings';

@Riverpod(keepAlive: true)
class ThemeModeNotifier extends _$ThemeModeNotifier {
  @override
  String build() {
    return ref.watch(appPrefsProvider).getString('theme_mode') ?? 'system';
  }

  Future<void> setMode(String mode) async {
    state = mode;
    try {
      await ref.read(appPrefsProvider).setString('theme_mode', mode);
    } catch (e) {
      Log.e(_tag, 'Failed to save theme mode', e);
    }
  }
}

@Riverpod(keepAlive: true)
class AccentColorNotifier extends _$AccentColorNotifier {
  @override
  int build() {
    return ref.watch(appPrefsProvider).getInt('accent_color') ??
        AppTheme.kPrimary.toARGB32();
  }

  Future<void> setColor(int color) async {
    state = color;
    try {
      await ref.read(appPrefsProvider).setInt('accent_color', color);
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
          _buildSection(context, 'Theme Mode'),
          RadioGroup<String>(
            groupValue: currentMode,
            onChanged: (v) {
              if (v != null) ref.read(themeModeProvider.notifier).setMode(v);
            },
            child: Column(
              children: _themeModes
                  .map(
                    (mode) => ListTile(
                      leading: Icon(
                        mode.$3,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: Text(mode.$2),
                      trailing: Radio<String>(value: mode.$1),
                      onTap: () =>
                          ref.read(themeModeProvider.notifier).setMode(mode.$1),
                    ),
                  )
                  .toList(),
            ),
          ),
          _buildSection(context, 'Accent Color'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _accentColors.map((c) {
                final isSelected = currentColor == c.$2.toARGB32();
                return GestureDetector(
                  onTap: () => ref
                      .read(accentColorProvider.notifier)
                      .setColor(c.$2.toARGB32()),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: c.$2,
                      borderRadius: BorderRadius.all(Radii.lg),
                      border: isSelected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: c.$2.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ]
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

  Widget _buildSection(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
