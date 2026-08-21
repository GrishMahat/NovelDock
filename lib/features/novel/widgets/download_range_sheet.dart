import 'package:flutter/material.dart';

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
  bool _useRange = false;
  late RangeValues _range;

  @override
  void initState() {
    super.initState();
    _range = RangeValues(widget.minChapter, widget.maxChapter);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Download Chapters',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Download range'),
            subtitle: Text(
              'Select chapter range (${widget.totalChapters} total)',
            ),
            value: _useRange,
            onChanged: (v) => setState(() => _useRange = v),
          ),
          if (_useRange) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Text(
                    'Chapters ${_range.start.round()} - ${_range.end.round()}',
                  ),
                  RangeSlider(
                    values: _range,
                    min: widget.minChapter,
                    max: widget.maxChapter,
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
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 4,
                    bottom: 16,
                  ),
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    right: 16,
                    bottom: 16,
                  ),
                  child: FilledButton(
                    onPressed: _useRange
                        ? () => widget.onDownloadRange(_range.start, _range.end)
                        : widget.onDownloadAll,
                    child: Text(_useRange ? 'Download Range' : 'Download All'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
