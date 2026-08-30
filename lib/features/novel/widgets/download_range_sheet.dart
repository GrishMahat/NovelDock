import 'package:flutter/material.dart';

import '../../../theme/tokens.dart';

class DownloadRangeSheet extends StatefulWidget {
  final int totalChapters;
  final double minChapter;
  final double maxChapter;
  final VoidCallback onDownloadAll;
  final void Function(double start, double end) onDownloadRange;

  const DownloadRangeSheet({
    super.key,
    required this.totalChapters,
    required this.minChapter,
    required this.maxChapter,
    required this.onDownloadAll,
    required this.onDownloadRange,
  });

  @override
  State<DownloadRangeSheet> createState() => _DownloadRangeSheetState();
}

class _DownloadRangeSheetState extends State<DownloadRangeSheet> {
  late RangeValues _range;
  bool _useRange = false;

  @override
  void initState() {
    super.initState();
    _range = RangeValues(
      widget.minChapter.toDouble(),
      widget.maxChapter.toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.xl,
              Insets.xs,
              Insets.xl,
              Insets.sm,
            ),
            child: Text(
              'Download Chapters',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SwitchListTile(
            title: const Text('Limit to a chapter range'),
            subtitle: Text(
              'Chapters ${widget.minChapter.round()} to ${widget.maxChapter.round()} (${widget.totalChapters} total)',
            ),
            value: _useRange,
            onChanged: (v) => setState(() => _useRange = v),
          ),
          if (_useRange)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              child: Column(
                children: [
                  Text(
                    'Chapters ${_range.start.round()} to ${_range.end.round()}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RangeSlider(
                    values: _range,
                    min: widget.minChapter.toDouble(),
                    max: widget.maxChapter.toDouble(),
                    divisions: (widget.maxChapter - widget.minChapter)
                        .toInt()
                        .clamp(1, 100),
                    labels: RangeLabels(
                      '${_range.start.round()}',
                      '${_range.end.round()}',
                    ),
                    onChanged: (v) => setState(() => _range = v),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.only(
              left: Insets.lg,
              right: Insets.lg,
              top: Insets.sm,
              bottom: MediaQuery.paddingOf(context).bottom + Insets.lg,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _useRange
                        ? () => widget.onDownloadRange(_range.start, _range.end)
                        : widget.onDownloadAll,
                    child: Text(_useRange ? 'Download range' : 'Download all'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
