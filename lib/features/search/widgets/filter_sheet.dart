import 'package:flutter/material.dart';

import '../../../core/providers/filters.dart';
import '../../../theme/tokens.dart';

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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.sm,
                Insets.sm,
                Insets.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filters',
                      style: Theme.of(context).textTheme.titleLarge,
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
                children: [
                  // Small option lists (status, sort, ...) come first; large
                  // lists (e.g. 50+ genres) sink to the bottom so they do not
                  // push the quick filters out of view.
                  for (final def in widget.defs.toList(
                    growable: false,
                  )..sort((a, b) => _optionCount(a).compareTo(_optionCount(b))))
                    _buildFilter(def),
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

  static int _optionCount(FilterDef def) {
    return switch (def) {
      TextFilterDef() => 0,
      SelectFilterDef d => d.options.length,
      MultiSelectFilterDef d => d.options.length,
      SortFilterDef d => d.options.length,
    };
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
            RadioGroup<int>(
              groupValue: currentIndex,
              onChanged: (value) {
                if (_isApplying || value == null) return;

                setState(() {
                  _values[d.id] = value;
                });
              },
              child: Column(
                children: [
                  for (var i = 0; i < d.options.length; i++)
                    RadioListTile<int>(
                      title: Text(d.options[i]),
                      value: i,
                      dense: true,
                    ),
                ],
              ),
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
            RadioGroup<int>(
              groupValue: index,
              onChanged: (value) {
                if (_isApplying || value == null) return;

                setState(() {
                  _values[d.id] = [value, ascending];
                });
              },
              child: Column(
                children: [
                  for (var i = 0; i < d.options.length; i++)
                    RadioListTile<int>(
                      title: Text(d.options[i]),
                      value: i,
                      dense: true,
                    ),
                ],
              ),
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
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.lg,
        Insets.lg,
        Insets.xs,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.sm,
                Insets.sm,
                Insets.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Search sources',
                      style: Theme.of(context).textTheme.titleLarge,
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
