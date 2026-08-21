import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/translation/translation_service.dart';
import '../../settings/pages/translation_settings_page.dart';

/// Shows a dialog for translating arbitrary text using the configured translation service.
void showTranslateDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  String? translatedText;
  bool isTranslating = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Translate Text'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Paste or type text to translate...',
                  border: OutlineInputBorder(),
                ),
              ),
              if (isTranslating) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (translatedText != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    translatedText!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: isTranslating
                ? null
                : () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;

                    setDialogState(() => isTranslating = true);

                    final translationSettings = ref.read(
                      translationSettingsProvider,
                    );
                    final service = ref.read(translationServiceProvider);
                    final result = await service.translate(
                      text,
                      sourceLang: translationSettings.fromLanguage,
                      targetLang: translationSettings.toLanguage,
                    );

                    setDialogState(() {
                      isTranslating = false;
                      translatedText = result;
                    });
                  },
            child: const Text('Translate'),
          ),
        ],
      ),
    ),
  );
}
