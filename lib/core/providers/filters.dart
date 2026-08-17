/// Tachiyomi-style filter model.
///
/// Providers declare filters via `getFilters()` in their JS. The app renders
/// them generically in a [FilterSheet]. Each provider keeps its own filter
/// values — there is no cross-provider (global) filter state.
library;

/// A single filter definition declared by a provider.
sealed class FilterDef {
  final String id;
  final String name;

  const FilterDef({required this.id, required this.name});

  factory FilterDef.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final name = json['name'] as String? ?? id;
    final options = (json['options'] as List?)?.cast<String>() ?? const [];
    switch (json['type'] as String? ?? 'text') {
      case 'select':
        return SelectFilterDef(
          id: id,
          name: name,
          options: options,
          defaultIndex: json['defaultIndex'] as int? ?? 0,
        );
      case 'multiselect':
        return MultiSelectFilterDef(
          id: id,
          name: name,
          options: options,
          defaultSelection:
              (json['defaultSelection'] as List?)?.cast<int>() ?? const [],
        );
      case 'sort':
        return SortFilterDef(
          id: id,
          name: name,
          options: options,
          defaultIndex: json['defaultIndex'] as int? ?? 0,
          defaultAscending: json['defaultAscending'] as bool? ?? true,
        );
      default:
        return TextFilterDef(
          id: id,
          name: name,
          defaultValue: json['defaultValue'] as String? ?? '',
        );
    }
  }
}

/// Free-text filter (e.g. title keyword).
class TextFilterDef extends FilterDef {
  final String defaultValue;
  const TextFilterDef({
    required super.id,
    required super.name,
    this.defaultValue = '',
  });
}

/// Single-choice filter; value is the selected option index (0 = first).
class SelectFilterDef extends FilterDef {
  final List<String> options;
  final int defaultIndex;
  const SelectFilterDef({
    required super.id,
    required super.name,
    required this.options,
    this.defaultIndex = 0,
  });
}

/// Multi-choice filter; value is a list of selected option indices.
class MultiSelectFilterDef extends FilterDef {
  final List<String> options;
  final List<int> defaultSelection;
  const MultiSelectFilterDef({
    required super.id,
    required super.name,
    required this.options,
    this.defaultSelection = const [],
  });
}

/// Sort filter; value is `[index, ascending]`.
class SortFilterDef extends FilterDef {
  final List<String> options;
  final int defaultIndex;
  final bool defaultAscending;
  const SortFilterDef({
    required super.id,
    required super.name,
    required this.options,
    this.defaultIndex = 0,
    this.defaultAscending = true,
  });
}

/// Current values for a provider's filters.
///
/// Values are what the provider JS receives:
/// - text: String (empty = unset)
/// - select: int (option index)
/// - multiselect: List<int> (option indices)
/// - sort: [int index, bool ascending]
class FilterValues {
  final Map<String, dynamic> values;

  const FilterValues([this.values = const {}]);

  bool get isEmpty => values.isEmpty;

  bool get isNotEmpty => values.isNotEmpty;

  factory FilterValues.fromJson(Map<String, dynamic> json) =>
      FilterValues(Map.of(json));

  Map<String, dynamic> toJson() => values;

  FilterValues copyWith(Map<String, dynamic> updated) =>
      FilterValues({...values, ...updated});
}

/// Default values for a provider's filters.
FilterValues defaultFilterValues(List<FilterDef> defs) {
  final values = <String, dynamic>{};
  for (final def in defs) {
    switch (def) {
      case TextFilterDef d:
        if (d.defaultValue.isNotEmpty) values[d.id] = d.defaultValue;
      case SelectFilterDef d:
        if (d.defaultIndex != 0) values[d.id] = d.defaultIndex;
      case MultiSelectFilterDef d:
        if (d.defaultSelection.isNotEmpty) values[d.id] = d.defaultSelection;
      case SortFilterDef d:
        if (d.defaultIndex != 0 || !d.defaultAscending) {
          values[d.id] = [d.defaultIndex, d.defaultAscending];
        }
    }
  }
  return FilterValues(values);
}