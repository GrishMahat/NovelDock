import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/database.dart';
import '../../../core/tts/tts_manager.dart';
import '../../../core/tts/tts_highlighter.dart';
import '../../../core/utils/html_chunker.dart';
import '../../settings/pages/reader_settings_page.dart';

/// A loaded chapter with its HTML content.
class LoadedChapter {
  final Chapter chapter;
  final String html;
  const LoadedChapter({required this.chapter, required this.html});
}

Map<String, String>? _alignmentStyles(ReaderSettings settings) {
  final alignment = settings.textAlignment;
  if (alignment == 'left' || alignment == 'center' || alignment == 'right' || alignment == 'justify') {
    return {'text-align': alignment};
  }
  return null;
}

TextStyle buildTextStyle(ReaderSettings settings) {
  return TextStyle(
    fontSize: settings.fontSize,
    fontFamily: settings.fontFamily.isEmpty ? null : settings.fontFamily,
    height: settings.lineHeight,
    color: settings.textColor,
  );
}

Widget buildChapterContent({
  required LoadedChapter loaded,
  required ReaderSettings settings,
  required TextStyle textStyle,
  required TtsManagerState ttsState,
  required int currentChapterId,
  required Map<String, GlobalKey> chunkKeys,
  required int settingsVersion,
}) {
  // PDF chapter
  if (loaded.html.startsWith('PDF:')) {
    final filePath = loaded.html.replaceFirst('PDF:', '');
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.picture_as_pdf, size: 64, color: settings.textColor.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            'PDF Document',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: settings.textColor),
          ),
          const SizedBox(height: 8),
          Text(
            filePath.split('/').last,
            style: TextStyle(color: settings.textColor.withValues(alpha: 0.5), fontSize: 12),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () async {
              final uri = Uri.file(filePath);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open in PDF Viewer'),
          ),
        ],
      ),
    );
  }

  // HTML/EPUB chapter — chunk and render paragraph by paragraph
  final isCurrentChapter = loaded.chapter.id == currentChapterId;

  final chunks = HtmlChunker.chunkHtml(loaded.html);
  final highlightKey = ttsState.isSpeaking ? '-${ttsState.currentChunkIndex}-${ttsState.currentWordIndex}' : '';

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final chunk in chunks) ...[
        Builder(
          builder: (context) {
            final isCurrentChunk = isCurrentChapter &&
                ttsState.isSpeaking &&
                chunk.index == ttsState.currentChunkIndex;

            var chunkHtml = chunk.rawHtml;
            if (isCurrentChunk) {
              chunkHtml = TtsHighlighter.highlightFromWordIndex(
                chunk.rawHtml,
                ttsState.currentWordIndex,
                ttsState.highlightMode,
              );
            }

            return KeyedSubtree(
              key: chunkKeys.putIfAbsent('${loaded.chapter.id}-${chunk.index}', () => GlobalKey()),
              child: HtmlWidget(
                chunkHtml,
                key: ValueKey('$settingsVersion-${settings.textAlignment}-${settings.fontSize}-${settings.fontFamily}${isCurrentChunk ? highlightKey : ''}'),
                textStyle: textStyle,
                customStylesBuilder: (element) {
                  final styles = _alignmentStyles(settings);
                  if (element.localName == 'span') {
                    final cls = element.attributes['class'] ?? '';
                    if (cls.contains('tts-highlight-word')) {
                      return <String, String>{
                        'background-color': 'rgba(61, 80, 250, 0.75)',
                        'color': '#ffffff',
                        'font-weight': 'bold',
                      };
                    } else if (cls.contains('tts-highlight')) {
                      return <String, String>{
                        'background-color': 'rgba(61, 80, 250, 0.22)',
                        'color': 'inherit',
                      };
                    }
                  }
                  return styles;
                },
              ),
            );
          },
        ),
      ],
    ],
  );
}

// ─── Continuous Mode ──────────────────────────────────────

Widget buildContinuousContent({
  required BuildContext context,
  required ReaderSettings settings,
  required List<Chapter> chapters,
  required int currentIndex,
  required Map<int, LoadedChapter> chapterCache,
  required ScrollController scrollController,
  required void Function(int) loadChapter,
  required Map<String, GlobalKey> chunkKeys,
  required int settingsVersion,
  required TtsManagerState ttsState,
}) {
  final textStyle = buildTextStyle(settings);

  return ListView.builder(
    controller: scrollController,
    padding: EdgeInsets.symmetric(horizontal: settings.paddingH, vertical: settings.paddingV),
    itemCount: chapters.length,
    itemBuilder: (context, index) {
      final loaded = chapterCache[chapters[index].id];
      if (loaded == null) {
        if (index <= currentIndex + 3) {
          loadChapter(index);
        }
        if (index == currentIndex + 1) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return const SizedBox(height: 300);
      }

      final isEpub = loaded.chapter.url.startsWith('epub://');
      if (index > 0 && !isEpub) {
        final currentChapterId = (chapters.isNotEmpty && currentIndex < chapters.length)
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
                    loaded.chapter.name,
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
              loaded: loaded,
              settings: settings,
              textStyle: textStyle,
              ttsState: ttsState,
              currentChapterId: currentChapterId,
              chunkKeys: chunkKeys,
              settingsVersion: settingsVersion,
            ),
          ],
        );
      }

      final currentChapterId = (chapters.isNotEmpty && currentIndex < chapters.length)
          ? chapters[currentIndex].id
          : -1;
      return buildChapterContent(
        loaded: loaded,
        settings: settings,
        textStyle: textStyle,
        ttsState: ttsState,
        currentChapterId: currentChapterId,
        chunkKeys: chunkKeys,
        settingsVersion: settingsVersion,
      );
    },
  );
}

// ─── Paged Mode ───────────────────────────────────────────

Widget buildPagedContent({
  required BuildContext context,
  required ReaderSettings settings,
  required List<Chapter> chapters,
  required int currentIndex,
  required Map<int, LoadedChapter> chapterCache,
  required PageController pageController,
  required void Function(int) onPageChanged,
  required void Function(int) loadChapter,
  required VoidCallback goToPreviousChapter,
  required VoidCallback goToNextChapter,
  required Map<String, GlobalKey> chunkKeys,
  required int settingsVersion,
  required TtsManagerState ttsState,
}) {
  final textStyle = buildTextStyle(settings);

  return Column(
    children: [
      Expanded(
        child: PageView.builder(
          controller: pageController,
          itemCount: chapters.length,
          onPageChanged: (index) {
            onPageChanged(index);
            loadChapter(index);
            if (index > 0) loadChapter(index - 1);
            if (index < chapters.length - 1) loadChapter(index + 1);
          },
          itemBuilder: (context, index) {
            final loaded = chapterCache[chapters[index].id];
            if (loaded == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final currentChapterId = (chapters.isNotEmpty && currentIndex < chapters.length)
                ? chapters[currentIndex].id
                : -1;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: settings.paddingH, vertical: settings.paddingV),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      loaded.chapter.name,
                      style: TextStyle(
                        color: settings.textColor,
                        fontSize: settings.fontSize + 4,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  buildChapterContent(
                    loaded: loaded,
                    settings: settings,
                    textStyle: textStyle,
                    ttsState: ttsState,
                    currentChapterId: currentChapterId,
                    chunkKeys: chunkKeys,
                    settingsVersion: settingsVersion,
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
              style: TextStyle(color: settings.textColor.withValues(alpha: 0.7), fontSize: 13),
            ),
            TextButton.icon(
              onPressed: currentIndex < chapters.length - 1 ? goToNextChapter : null,
              icon: const Text('Next'),
              label: const Icon(Icons.chevron_right, size: 20),
            ),
          ],
        ),
      ),
    ],
  );
}
