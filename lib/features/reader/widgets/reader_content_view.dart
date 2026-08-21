import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/content/content_model.dart';
import '../../../core/content/markdown/md_parser.dart';
import '../../../core/content/markdown/md_renderer.dart';
import '../../../core/tts/tts_manager.dart';
import '../../../core/database/database.dart';
import '../../settings/pages/reader/reader_settings_state.dart';

Widget buildChapterContent({
  required ChapterContent content,
  required int currentChapterId,
  required ReaderSettings settings,
  required TtsManagerState ttsState,
  required Map<String, GlobalKey> chunkKeys,
  required int settingsVersion,
  Map<int, int>? blockToParagraph,
}) {
  if (content.isPdf) {
    return _buildPdfView(content.data, settings);
  }

  final doc = MDParser.parse(content.data);

  return buildDocument(
    doc: doc,
    chapterId: content.chapterId,
    currentChapterId: currentChapterId,
    settings: settings,
    ttsState: ttsState,
    chunkKeys: chunkKeys,
    settingsVersion: settingsVersion,
    blockToParagraph: blockToParagraph,
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
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: settings.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _fileNameOf(filePath),
            style: TextStyle(
              color: settings.textColor.withValues(alpha: 0.5),
              fontSize: 12,
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
        if (index == currentIndex + 1) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return const SizedBox(height: 300);
      }

      if (chapterError != null) {
        return _buildChapterError(chapterError, settings);
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
                    style: TextStyle(
                      color: settings.textColor.withValues(alpha: 0.4),
                      fontSize: 12,
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
      );
    },
  );
}

Widget _buildChapterError(String error, ReaderSettings settings) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        Text(
          error,
          style: TextStyle(color: settings.textColor),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
      ],
    ),
  );
}

// ─── Paged Mode ───────────────────────────────────────────

Widget buildPagedContent({
  required BuildContext context,
  required ReaderSettings settings,
  required List<Chapter> chapters,
  required int currentIndex,
  required Map<int, ChapterContent>? contentCache,
  required Map<int, String>? errorCache,
  required PageController pageController,
  required void Function(int) onPageChanged,
  required void Function(int) loadChapter,
  required VoidCallback goToPreviousChapter,
  required VoidCallback goToNextChapter,
  required Map<String, GlobalKey> chunkKeys,
  required int settingsVersion,
  required TtsManagerState ttsState,
  Map<int, int>? blockToParagraph,
}) {
  return Column(
    children: [
      Expanded(
        child: PageView.builder(
          controller: pageController,
          itemCount: chapters.length,
          onPageChanged: (index) {
            onPageChanged(index);
            loadChapter(chapters[index].id);
            if (index > 0) loadChapter(chapters[index - 1].id);
            if (index < chapters.length - 1) {
              loadChapter(chapters[index + 1].id);
            }
          },
          itemBuilder: (context, index) {
            final chapterId = chapters[index].id;
            final content = contentCache?[chapterId];
            final error = errorCache?[chapterId];
            if (content == null && error == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (error != null) {
              return _buildChapterError(error, settings);
            }
            final currentChapterId =
                (chapters.isNotEmpty && currentIndex < chapters.length)
                ? chapters[currentIndex].id
                : -1;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: settings.paddingH,
                vertical: settings.paddingV,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      chapters[index].name,
                      style: TextStyle(
                        color: settings.textColor,
                        fontSize: settings.fontSize + 4,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  buildChapterContent(
                    content: content!,
                    currentChapterId: currentChapterId,
                    settings: settings,
                    ttsState: ttsState,
                    chunkKeys: chunkKeys,
                    settingsVersion: settingsVersion,
                    blockToParagraph: blockToParagraph,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      Container(
        color: settings.bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: currentIndex > 0 ? goToPreviousChapter : null,
              icon: const Icon(Icons.chevron_left, size: 20),
              label: const Text('Previous'),
            ),
            Text(
              '${currentIndex + 1} / ${chapters.length}',
              style: TextStyle(
                color: settings.textColor.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            TextButton.icon(
              onPressed: currentIndex < chapters.length - 1
                  ? goToNextChapter
                  : null,
              icon: const Icon(Icons.chevron_right, size: 20),
              label: const Text('Next'),
            ),
          ],
        ),
      ),
    ],
  );
}
