import 'package:flutter/material.dart';

import '../../../core/database/database.dart';
import '../../../theme/tokens.dart';
import '../../settings/pages/reader/reader_settings_state.dart';

/// Floating chapter panel that slides in over the reading column's right
/// edge on desktop. Revealed by hovering the right edge; hidden on leave.
/// Colors derive from the active reader theme so it sits well on any of
/// the five reader backgrounds.
class ChapterSidebar extends StatefulWidget {
  final List<Chapter> chapters;
  final int currentIndex;
  final ReaderSettings settings;
  final ValueChanged<int> onJumpToChapter;
  final VoidCallback onClose;

  const ChapterSidebar({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.settings,
    required this.onJumpToChapter,
    required this.onClose,
  });

  @override
  State<ChapterSidebar> createState() => _ChapterSidebarState();
}

class _ChapterSidebarState extends State<ChapterSidebar> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _filterController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void didUpdateWidget(ChapterSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    final extent = _scrollController.position.maxScrollExtent;
    if (extent <= 0) return;
    final ratio = widget.chapters.isEmpty
        ? 0.0
        : widget.currentIndex / widget.chapters.length;
    _scrollController.jumpTo((ratio * extent).clamp(0.0, extent));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final surface = Color.alphaBlend(
      s.textColor.withValues(alpha: 0.07),
      s.bgColor,
    );
    final hairline = s.textColor.withValues(alpha: 0.18);
    final query = _query.trim().toLowerCase();

    // Map filtered chapters to their real indices for jumping.
    final indices = <int>[
      for (var i = 0; i < widget.chapters.length; i++)
        if (query.isEmpty ||
            widget.chapters[i].name.toLowerCase().contains(query))
          i,
    ];

    return Padding(
      padding: const EdgeInsets.all(Insets.sm),
      child: Material(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(color: hairline),
        ),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: Container(
          width: Desktop.readerSidebarWidth - Insets.sm * 2,
          decoration: BoxDecoration(borderRadius: Radii.card),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.md,
                  Insets.sm,
                  Insets.xs,
                  Insets.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chapters (${widget.chapters.length})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: s.textColor),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 20, color: s.textColor),
                      tooltip: 'Hide chapter list',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.md,
                  Insets.xs,
                  Insets.md,
                  Insets.sm,
                ),
                child: TextField(
                  controller: _filterController,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: s.textColor),
                  decoration: InputDecoration(
                    hintText: 'Filter chapters',
                    hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: s.textColor.withValues(alpha: 0.5),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 16,
                      color: s.textColor.withValues(alpha: 0.6),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: Insets.sm,
                    ),
                    filled: true,
                    fillColor: s.textColor.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Divider(height: 1, color: hairline),
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                    itemCount: indices.length,
                    itemBuilder: (context, listIndex) {
                      final index = indices[listIndex];
                      final chapter = widget.chapters[index];
                      final isCurrent = index == widget.currentIndex;
                      return ListTile(
                        dense: true,
                        selected: isCurrent,
                        selectedTileColor: s.textColor.withValues(alpha: 0.12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.sm.x),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: Insets.md,
                        ),
                        minLeadingWidth: 28,
                        leading: SizedBox(
                          width: 28,
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: isCurrent
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isCurrent
                                      ? s.textColor
                                      : s.textColor.withValues(alpha: 0.55),
                                ),
                          ),
                        ),
                        title: Text(
                          chapter.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isCurrent
                                    ? s.textColor
                                    : s.textColor.withValues(alpha: 0.75),
                              ),
                        ),
                        onTap: () => widget.onJumpToChapter(index),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
