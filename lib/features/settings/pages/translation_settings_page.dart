import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/app_theme.dart';

/// Translation settings
class TranslationSettings {
  final String fromLanguage;
  final String toLanguage;
  final bool useOnlineTranslation;
  final bool autoTranslate;

  const TranslationSettings({
    this.fromLanguage = 'auto',
    this.toLanguage = 'en',
    this.useOnlineTranslation = false,
    this.autoTranslate = false,
  });

  TranslationSettings copyWith({
    String? fromLanguage,
    String? toLanguage,
    bool? useOnlineTranslation,
    bool? autoTranslate,
  }) {
    return TranslationSettings(
      fromLanguage: fromLanguage ?? this.fromLanguage,
      toLanguage: toLanguage ?? this.toLanguage,
      useOnlineTranslation: useOnlineTranslation ?? this.useOnlineTranslation,
      autoTranslate: autoTranslate ?? this.autoTranslate,
    );
  }
}

class TranslationSettingsNotifier extends StateNotifier<TranslationSettings> {
  TranslationSettingsNotifier() : super(const TranslationSettings()) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = TranslationSettings(
      fromLanguage: p.getString('translation_from') ?? 'auto',
      toLanguage: p.getString('translation_to') ?? 'en',
      useOnlineTranslation: p.getBool('translation_online') ?? false,
      autoTranslate: p.getBool('translation_auto') ?? false,
    );
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('translation_from', state.fromLanguage);
    await p.setString('translation_to', state.toLanguage);
    await p.setBool('translation_online', state.useOnlineTranslation);
    await p.setBool('translation_auto', state.autoTranslate);
  }

  void _update(TranslationSettings Function(TranslationSettings) updater) {
    state = updater(state);
    _save();
  }

  void updateFromLanguage(String v) =>
      _update((s) => s.copyWith(fromLanguage: v));
  void updateToLanguage(String v) => _update((s) => s.copyWith(toLanguage: v));
  void toggleOnlineTranslation() =>
      _update((s) => s.copyWith(useOnlineTranslation: !s.useOnlineTranslation));
  void toggleAutoTranslate() =>
      _update((s) => s.copyWith(autoTranslate: !s.autoTranslate));
}

final translationSettingsProvider =
    StateNotifierProvider<TranslationSettingsNotifier, TranslationSettings>((
      ref,
    ) {
      return TranslationSettingsNotifier();
    });

/// Supported languages for translation
const _languages = [
  ('auto', 'Auto Detect'),
  ('en', 'English'),
  ('ru', 'Russian'),
  ('uk', 'Ukrainian'),
  ('es', 'Spanish'),
  ('fr', 'French'),
  ('de', 'German'),
  ('it', 'Italian'),
  ('pt', 'Portuguese'),
  ('zh', 'Chinese'),
  ('ja', 'Japanese'),
  ('ko', 'Korean'),
  ('ar', 'Arabic'),
  ('hi', 'Hindi'),
  ('tr', 'Turkish'),
  ('pl', 'Polish'),
  ('nl', 'Dutch'),
  ('sv', 'Swedish'),
];

class TranslationSettingsPage extends ConsumerWidget {
  const TranslationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(translationSettingsProvider);
    final notifier = ref.read(translationSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Translation Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection('Language'),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Source Language'),
            subtitle: Text(_getLanguageName(settings.fromLanguage)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguagePicker(context, ref, true),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Target Language'),
            subtitle: Text(_getLanguageName(settings.toLanguage)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showLanguagePicker(context, ref, false),
          ),

          const SizedBox(height: 16),
          _buildSection('Mode'),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Online Translation'),
            subtitle: const Text('Use Google Translate (requires internet)'),
            value: settings.useOnlineTranslation,
            onChanged: (_) => notifier.toggleOnlineTranslation(),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-translate'),
            subtitle: const Text(
              'Translate chapters automatically when reading',
            ),
            value: settings.autoTranslate,
            onChanged: (_) => notifier.toggleAutoTranslate(),
          ),

          const SizedBox(height: 16),
          _buildSection('About'),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Translation Engine',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Offline mode uses Google ML Kit for on-device translation. '
                    'Online mode uses Google Translate API (no key required). '
                    'Offline translations are cached locally.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getLanguageName(String code) {
    for (final (c, name) in _languages) {
      if (c == code) return name;
    }
    return code;
  }

  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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

  void _showLanguagePicker(BuildContext context, WidgetRef ref, bool isSource) {
    final notifier = ref.read(translationSettingsProvider.notifier);
    final current = isSource
        ? ref.read(translationSettingsProvider).fromLanguage
        : ref.read(translationSettingsProvider).toLanguage;

    final options = isSource
        ? _languages
        : _languages.where((l) => l.$1 != 'auto').toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                isSource ? 'Source Language' : 'Target Language',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: options.length,
                itemBuilder: (ctx, index) {
                  final (code, name) = options[index];
                  final isSelected = current == code;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected ? AppTheme.kPrimary : null,
                    ),
                    title: Text(name),
                    subtitle: Text(code, style: const TextStyle(fontSize: 12)),
                    onTap: () {
                      if (isSource) {
                        notifier.updateFromLanguage(code);
                      } else {
                        notifier.updateToLanguage(code);
                      }
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
