import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/log_buffer.dart';
import '../../../core/utils/logger.dart';

class LogViewerPage extends ConsumerStatefulWidget {
  const LogViewerPage({super.key});

  @override
  ConsumerState<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends ConsumerState<LogViewerPage> {
  final _scrollController = ScrollController();
  final _filterController = TextEditingController();
  String _filterText = '';
  bool _autoScroll = true;
  LogLevel? _levelFilter;

  @override
  void dispose() {
    _scrollController.dispose();
    _filterController.dispose();
    super.dispose();
  }

  List<LogEntry> _filter(List<LogEntry> entries) {
    var result = entries;
    if (_levelFilter != null) {
      result = result.where((e) => e.level == _levelFilter!).toList();
    }
    if (_filterText.isNotEmpty) {
      final lower = _filterText.toLowerCase();
      result = result.where((e) =>
        e.tag.toLowerCase().contains(lower) ||
        e.message.toLowerCase().contains(lower)
      ).toList();
    }
    return result;
  }

  Future<void> _copyAll() async {
    final entries = globalLogBuffer.entries;
    final text = entries.map((e) => e.formatted).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied ${entries.length} log entries')),
      );
    }
  }

  void _addTestLog() {
    Log.i('Debug', 'This is an info log');
    Log.d('Debug', 'Debug message test');
    Log.w('Debug', 'Warning test message');
    Log.e('Debug', 'Error test message');
  }

  @override
  Widget build(BuildContext context) {
    final asyncEntries = ref.watch(logBufferProvider);
    final entries = asyncEntries.asData?.value ?? [];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoScroll && _scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        if (_scrollController.offset < max - 50) {
          _scrollController.animateTo(
            max,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      }
    });

    final filtered = _filter(entries);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Viewer'),
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_center),
            tooltip: 'Auto-scroll',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Add test log',
            onPressed: _addTestLog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear',
            onPressed: () => globalLogBuffer.clear(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                ...LogLevel.values.map((level) {
                  final selected = _levelFilter == level;
                  final color = switch (level) {
                    LogLevel.debug => Colors.grey,
                    LogLevel.info => Colors.blue,
                    LogLevel.warning => Colors.orange,
                    LogLevel.error => Colors.red,
                  };
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: FilterChip(
                      label: Text(level.name, style: const TextStyle(fontSize: 11)),
                      selected: selected,
                      onSelected: (_) => setState(() {
                        _levelFilter = selected ? null : level;
                      }),
                      selectedColor: color.withValues(alpha: 0.3),
                      checkmarkColor: color,
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                hintText: 'Filter by tag or message...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _filterText.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _filterController.clear();
                          setState(() => _filterText = '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (v) => setState(() => _filterText = v),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Text(
                  '${filtered.length} / ${entries.length} entries',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                if (entries.isNotEmpty)
                  Text(
                    entries.last.formatted.split(' ').first,
                    style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      entries.isEmpty ? 'No log entries yet' : 'No matching entries',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final entry = filtered[index];
                      final color = switch (entry.level) {
                        LogLevel.debug => Colors.grey,
                        LogLevel.info => null,
                        LogLevel.warning => Colors.orange.shade300,
                        LogLevel.error => Colors.red.shade300,
                      };
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                        child: Text(
                          entry.formatted,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: color,
                            height: 1.3,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
