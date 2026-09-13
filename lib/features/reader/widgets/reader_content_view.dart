import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/content/content_model.dart';
import '../../../core/content/markdown/md_parser.dart';
import '../../../core/content/markdown/md_renderer.dart';
import '../../../core/tts/tts_manager.dart';
import '../../../core/database/database.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/shimmer_list.dart';
import '../../settings/pages/reader/reader_settings_state.dart';

Widget buildChapterContent({
  required ChapterContent content,
  required int currentChapterId,
  required ReaderSettings settings,
  required TtsManagerState ttsState,
  required Map<String, GlobalKey> chunkKeys,
  required int settingsVersion,
  Map<int, int>? blockToParagraph,
  Map<int, Annotation>? annotationsByParagraph,
  void Function(int chapterId, int paragraphIndex, String text)?
  onAnnotateParagraph,
  Map<String, String>? imageHeaders,
}) {
  if (content.isPdf) {
    return _buildPdfView(content.data, settings);
  }

  final doc = MDParser.parse(content.data);

  // A 0-paragraph intake result is not a loading state: say so instead of
  // rendering a blank that looks broken.
  if (doc.blocks.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Center(
        child: Text(
          'This chapter has no readable text.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: settings.textColor.withValues(alpha: 0.65),
            fontSize: settings.fontSize,
          ),
        ),
      ),
    );
  }

  return buildDocument(
    doc: doc,
    chapterId: content.chapterId,
    currentChapterId: currentChapterId,
    settings: settings,
    ttsState: ttsState,
    chunkKeys: chunkKeys,
    settingsVersion: settingsVersion,
    blockToParagraph: blockToParagraph,
    annotationsByParagraph: annotationsByParagraph,
    onAnnotateParagraph: onAnnotateParagraph,
    imageHeaders: imageHeaders ?? content.imageHeaders,
  );
}

/// Returns just the filename portion of a path, handling both
/// Unix ('/') and Windows ('\') separators regardless of which
/// platform the app is currently running on.
String _fileNameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final segments = normalized.split('/');
  return segments.isNotEmpty ? segments.last : path;
}

Widget _buildPdfView(String filePath, ReaderSettings settings) {
  return Builder(
    builder: (context) => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.picture_as_pdf,
            size: 64,
            color: settings.textColor.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'PDF Document',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: settings.textColor),
          ),
          const SizedBox(height: 8),
          Text(
            _fileNameOf(filePath),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: settings.textColor.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              final uri = Uri.file(filePath);
              final launched =
                  await canLaunchUrl(uri) &&
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!launched && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not find an app to open this PDF.'),
                  ),
                );
              }
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open in PDF Viewer'),
          ),
        ],
      ),
    ),
  );
}

// ─── Continuous Mode ──────────────────────────────────────

Widget buildContinuousContent({
  required BuildContext context,
  required ReaderSettings settings,
  required List<Chapter> chapters,
  required int currentIndex,
  required Map<int, ChapterContent>? contentCache,
  required Map<int, String>? errorCache,
  required ScrollController scrollController,
  required void Function(int) loadChapter,
  required Map<String, GlobalKey> chunkKeys,
  required int settingsVersion,
  required TtsManagerState ttsState,
  Map<int, int>? blockToParagraph,
  Map<int, List<Annotation>>? annotationsByChapter,
  void Function(int chapterId, int paragraphIndex, String text)?
  onAnnotateParagraph,
}) {
  return ListView.builder(
    controller: scrollController,
    // Render well ahead of the viewport so anchor restore and TTS seeks
    // find their target chunks quickly on long chapters.
    scrollCacheExtent: ScrollCacheExtent.pixels(4000),
    padding: EdgeInsets.symmetric(
      horizontal: settings.paddingH,
      vertical: settings.paddingV,
    ),
    itemCount: chapters.length,
    itemBuilder: (context, index) {
      final chapterId = chapters[index].id;
      final contentEntry = contentCache?[chapterId];
      final chapterError = errorCache?[chapterId];

      if (contentEntry == null && chapterError == null) {
        if (index <= currentIndex + 3) {
          loadChapter(chapterId);
        }
        // Prose-shaped shimmer like the far-chapter placeholder below: a
        // bare spinner here flashes layout on every chapter turn.
        // Static on e-ink (no animation burn on epaper).
        final placeholderHeight = index == currentIndex + 1
            ? 320.0
            : 240.0 + ((chapterId * 37) % 5) * 32.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: ShimmerBlock(
            height: placeholderHeight,
            enabled: !settings.reduceMotion,
          ),
        );
      }

      if (chapterError != null) {
        return _buildChapterError(
          chapterError,
          settings,
          onRetry: () => loadChapter(chapterId),
        );
      }

      final isEpub = chapters[index].url.startsWith('epub://');
      if (index > 0 && !isEpub) {
        final currentChapterId =
            (chapters.isNotEmpty && currentIndex < chapters.length)
            ? chapters[currentIndex].id
            : -1;
        return Column(
          children: [
            const SizedBox(height: 64),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Container(
                    height: 1,
                    color: settings.textColor.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Chapter ${index + 1}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: settings.textColor.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    chapters[index].name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: settings.textColor,
                      fontSize: settings.fontSize + 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 1,
                    color: settings.textColor.withValues(alpha: 0.2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            buildChapterContent(
              content: contentEntry!,
              currentChapterId: currentChapterId,
              settings: settings,
              ttsState: ttsState,
              chunkKeys: chunkKeys,
              settingsVersion: settingsVersion,
              blockToParagraph: blockToParagraph,
              annotationsByParagraph: _annotationsFor(
                annotationsByChapter,
                chapterId,
              ),
              onAnnotateParagraph: onAnnotateParagraph,
            ),
          ],
        );
      }

      final currentChapterId =
          (chapters.isNotEmpty && currentIndex < chapters.length)
          ? chapters[currentIndex].id
          : -1;
      return buildChapterContent(
        content: contentEntry!,
        currentChapterId: currentChapterId,
        settings: settings,
        ttsState: ttsState,
        chunkKeys: chunkKeys,
        settingsVersion: settingsVersion,
        blockToParagraph: blockToParagraph,
        annotationsByParagraph: _annotationsFor(
          annotationsByChapter,
          chapterId,
        ),
        onAnnotateParagraph: onAnnotateParagraph,
      );
    },
  );
}

/// Paragraph-indexed annotation lookup for one chapter. Null-safe: no
/// annotations (or none for this chapter) means plain rendering.
Map<int, Annotation>? _annotationsFor(
  Map<int, List<Annotation>>? byChapter,
  int chapterId,
) {
  final rows = byChapter?[chapterId];
  if (rows == null || rows.isEmpty) return null;
  return {for (final a in rows) a.paragraphIndex: a};
}

/// One failed chapter is a retryable event, not a dead end. Raw exception
/// strings (e.g. "Exception: Chapter 12 not found in database") are mapped
/// to human language; the unmapped remainder is shown without the
/// "Exception:" prefix.
Widget _buildChapterError(
  String error,
  ReaderSettings settings, {
  required VoidCallback onRetry,
}) {
  final message = _humanChapterError(error);
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppTheme.kReaderError,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: settings.textColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

String _humanChapterError(String error) {
  final clean = error.replaceFirst(RegExp(r'^Exception:\s*'), '');
  if (clean.contains('not found in database')) {
    return 'This chapter is missing from the library. Pull to refresh the novel, then try again.';
  }
  if (clean.contains('Could not determine chapter URL')) {
    return 'The source did not provide a readable address for this chapter.';
  }
  if (clean.contains('SocketException') ||
      clean.contains('Connection refused') ||
      clean.contains('Connection reset') ||
      clean.contains('Failed host lookup') ||
      clean.contains('TimeoutException') ||
      clean.contains('timed out')) {
    return 'Could not reach the source. Check your connection and retry.';
  }
  if (clean.contains('404')) {
    return 'The source no longer has this chapter (404).';
  }
  if (clean.contains('403') || clean.contains('Cloudflare')) {
    return 'The source blocked this request. Open it once in Browse so any verification completes, then retry.';
  }
  return clean;
}
