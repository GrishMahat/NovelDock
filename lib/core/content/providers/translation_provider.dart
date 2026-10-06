import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/translation/translation_service.dart';
import '../../../features/settings/pages/translation_settings_page.dart';
import '../markdown/md_paragraphs.dart';
import '../markdown/md_parser.dart';
import 'content_provider.dart';

part 'translation_provider.g.dart';

@Riverpod()
Future<String?> chapterTranslation(Ref ref, int chapterId) async {
  final content = ref.watch(contentProvider.notifier).getContentMd(chapterId);
  if (content == null) return null;

  final settings = ref.read(translationSettingsProvider);
  if (settings.fromLanguage == settings.toLanguage) return null;

  final doc = MDParser.parse(content);
  // Same canonical paragraphs TTS speaks: formatted runs are flattened,
  // not dropped (a naive whereType<TextNode>() scan loses bold/italic).
  final paragraphs = [
    for (final p in extractParagraphs(doc)) p.text.trim(),
  ].where((t) => t.isNotEmpty).toList();

  if (paragraphs.isEmpty) return null;

  final service = ref.read(translationServiceProvider);
  final translated = <String>[];
  var changed = false;
  for (final para in paragraphs) {
    final result = await service.translate(
      para,
      sourceLang: settings.fromLanguage,
      targetLang: settings.toLanguage,
      // Online Translation off = offline mode: cache lookups only.
      allowNetwork: settings.useOnlineTranslation,
    );
    if (result != para) changed = true;
    translated.add(result);
  }

  // Nothing came back translated (offline + cache miss): let the reader keep
  // the original chapter instead of re-rendering flattened plain text.
  if (!changed) return null;

  return translated.join('\n\n');
}
