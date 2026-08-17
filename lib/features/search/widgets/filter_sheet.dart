import 'package:flutter/material.dart';

import '../../../core/providers/filters.dart';

/// Generic bottom-sheet filter UI rendered from provider-declared [FilterDef]s.
class FilterSheet extends StatefulWidget {
  final List<FilterDef> defs;
  final FilterValues initial;
  final Future<void> Function(FilterValues values) onApply;

  const FilterSheet({
    super.key,
    required this.defs,
    required this.initial,
    required this.onApply,
  });

  /// Convenience: show the sheet and return the applied [FilterValues]
  /// (or null if dismissed without applying).
  static Future<FilterValues?> show(
    BuildContext context, {
    required List<FilterDef> defs,
    required FilterValues initial,
    required Future<void> Function(FilterValues values) onApply,
  }) {
    return showModalBottomSheet<FilterValues>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) =>
          FilterSheet(defs: defs, initial: initial, onApply: onApply),
    );
  }

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late final Map<String, dynamic> _values;
  final Map<String, TextEditingController> _textControllers = {};

  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _values = Map<String, dynamic>.of(widget.initial.values);
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _textController(String id) {
    return _textControllers.putIfAbsent(
      id,
      () => TextEditingController(text: (_values[id] as String?) ?? ''),
    );
  }

  void _reset() {
    if (_isApplying) return;

    setState(() {
      _values.clear();

      for (final controller in _textControllers.values) {
        controller.clear();
      }
    });
  }

  Future<void> _apply() async {
    if (_isApplying) return;

    final applied = FilterValues(Map<String, dynamic>.of(_values));

    setState(() {
      _isApplying = true;
    });

    try {
      await widget.onApply(applied);

      if (!mounted) return;

      Navigator.pop(context, applied);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isApplying = false;
      });

      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _isApplying ? null : _reset,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 12),
                children: [for (final def in widget.defs) _buildFilter(def)],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isApplying ? null : _apply,
                    child: _isApplying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Apply'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilter(FilterDef def) {
    switch (def) {
      case TextFilterDef d:
        final controller = _textController(d.id);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: controller,
            enabled: !_isApplying,
            decoration: InputDecoration(
              labelText: d.name,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) {
              _values[d.id] = value;
            },
          ),
        );

      case SelectFilterDef d:
        final currentIndex = (_values[d.id] as int?) ?? d.defaultIndex;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(d.name),
            for (var i = 0; i < d.options.length; i++)
              RadioListTile<int>(
                title: Text(d.options[i]),
                value: i,
                dense: true,
                groupValue: currentIndex,
                onChanged: _isApplying
                    ? null
                    : (value) {
                        if (value == null) return;

                        setState(() {
                          _values[d.id] = value;
                        });
                      },
              ),
          ],
        );

      case MultiSelectFilterDef d:
        final selected = ((_values[d.id] as List?) ?? d.defaultSelection)
            .whereType<int>()
            .toSet();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(d.name),
            for (var i = 0; i < d.options.length; i++)
              CheckboxListTile(
                title: Text(d.options[i]),
                value: selected.contains(i),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: _isApplying
                    ? null
                    : (checked) {
                        setState(() {
                          if (checked == true) {
                            selected.add(i);
                          } else {
                            selected.remove(i);
                          }

                          _values[d.id] = selected.toList();
                        });
                      },
              ),
          ],
        );

      case SortFilterDef d:
        final current =
            (_values[d.id] as List?) ?? [d.defaultIndex, d.defaultAscending];

        final index = (current.isNotEmpty && current[0] is num)
            ? (current[0] as num).toInt()
            : d.defaultIndex;

        final ascending = current.length > 1 && current[1] is bool
            ? current[1] as bool
            : d.defaultAscending;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(d.name),
            for (var i = 0; i < d.options.length; i++)
              RadioListTile<int>(
                title: Text(d.options[i]),
                value: i,
                dense: true,
                groupValue: index,
                onChanged: _isApplying
                    ? null
                    : (value) {
                        if (value == null) return;

                        setState(() {
                          _values[d.id] = [value, ascending];
                        });
                      },
              ),
            SwitchListTile(
              title: const Text('Ascending'),
              subtitle: const Text('Toggle sort direction'),
              value: ascending,
              dense: true,
              onChanged: _isApplying
                  ? null
                  : (value) {
                      setState(() {
                        _values[d.id] = [index, value];
                      });
                    },
            ),
          ],
        );
    }
  }

  Widget _header(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// Source-picker sheet for choosing which providers a global search uses.
class SearchSourcesSheet extends StatefulWidget {
  final List<MapEntry<String, String>> providers;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const SearchSourcesSheet({
    super.key,
    required this.providers,
    required this.selected,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required List<MapEntry<String, String>> providers,
    required Set<String> selected,
    required ValueChanged<Set<String>> onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => SearchSourcesSheet(
        providers: providers,
        selected: selected,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<SearchSourcesSheet> createState() => _SearchSourcesSheetState();
}

class _SearchSourcesSheetState extends State<SearchSourcesSheet> {
  late final Set<String> _current;

  @override
  void initState() {
    super.initState();
    _current = Set<String>.from(widget.selected);
  }

  void _selectAll() {
    setState(() {
      _current
        ..clear()
        ..addAll(widget.providers.map((entry) => entry.key));
    });
  }

  void _clearAll() {
    setState(_current.clear);
  }

  void _apply() {
    final result = Set<String>.unmodifiable(_current);

    widget.onChanged(result);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final allSelected =
        widget.providers.isNotEmpty &&
        _current.length == widget.providers.length &&
        widget.providers.every((entry) => _current.contains(entry.key));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Search sources',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (allSelected)
                    TextButton(
                      onPressed: _clearAll,
                      child: const Text('Clear all'),
                    )
                  else
                    TextButton(
                      onPressed: _selectAll,
                      child: const Text('Select all'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.providers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No enabled sources available.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      controller: scrollController,
                      children: [
                        for (final entry in widget.providers)
                          CheckboxListTile(
                            title: Text(entry.value),
                            value: _current.contains(entry.key),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _current.add(entry.key);
                                } else {
                                  _current.remove(entry.key);
                                }
                              });
                            },
                          ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _apply,
                    child: Text(
                      _current.isEmpty
                          ? 'Search no sources'
                          : 'Search these sources',
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
