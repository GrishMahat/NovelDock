import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/translation/translation_service.dart';
import '../../../features/settings/pages/translation_settings_page.dart';
import '../markdown/md_ast.dart';
import '../markdown/md_parser.dart';
import 'content_provider.dart';

final chapterTranslationProvider = FutureProvider.family<String?, int>((
  ref,
  chapterId,
) async {
  final content = ref.watch(contentProvider.notifier).getContentMd(chapterId);
  if (content == null) return null;

  final settings = ref.read(translationSettingsProvider);
  if (settings.fromLanguage == settings.toLanguage) return null;

  final doc = MDParser.parse(content);
  final paragraphs = <String>[];
  for (final block in doc.blocks) {
    if (block is ParagraphNode) {
      final text = block.children
          .whereType<TextNode>()
          .map((n) => n.text)
          .join();
      if (text.trim().isNotEmpty) paragraphs.add(text.trim());
    }
  }

  if (paragraphs.isEmpty) return null;

  final service = ref.read(translationServiceProvider);
  final translated = <String>[];
  for (final para in paragraphs) {
    final result = await service.translate(
      para,
      sourceLang: settings.fromLanguage,
      targetLang: settings.toLanguage,
    );
    translated.add(result);
  }

  return translated.join('\n\n');
});
