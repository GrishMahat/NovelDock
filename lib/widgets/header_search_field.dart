import 'package:flutter/material.dart';

/// Compact search field for [PageHeader] action rows. Mirrors the global
/// top-bar search styling (pill radius, filled surface) at header scale.
class HeaderSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;

  const HeaderSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.onSubmitted,
    this.controller,
  });

  @override
  State<HeaderSearchField> createState() => _HeaderSearchFieldState();
}

class _HeaderSearchFieldState extends State<HeaderSearchField> {
  TextEditingController? _ownController;

  TextEditingController get _effective =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: TextField(
        controller: _effective,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          suffixIcon: _effective.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Clear filter',
                  onPressed: () {
                    _effective.clear();
                    widget.onChanged('');
                  },
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textInputAction: widget.onSubmitted != null
            ? TextInputAction.search
            : TextInputAction.done,
      ),
    );
  }
}
