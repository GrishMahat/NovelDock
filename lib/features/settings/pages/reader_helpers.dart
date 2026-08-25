import 'package:flutter/material.dart';

import '../../../core/tts/tts_manager.dart';
import '../../../theme/tokens.dart';

Widget section(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: Insets.sm),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

Widget tile(
  BuildContext context, {
  required String title,
  String? subtitle,
  VoidCallback? onTap,
}) {
  return ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle != null
        ? Text(subtitle, style: Theme.of(context).textTheme.bodySmall)
        : null,
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}

Widget slider(
  BuildContext context,
  String label,
  double value,
  double min,
  double max,
  String display,
  ValueChanged<double> onChanged,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
    child: Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(
          width: 50,
          child: Text(display, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

Widget switchTile(
  BuildContext context,
  String title,
  String? subtitle,
  bool value,
  ValueChanged<bool> onChanged,
) {
  return SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle != null
        ? Text(subtitle, style: Theme.of(context).textTheme.bodySmall)
        : null,
    value: value,
    onChanged: onChanged,
  );
}

Widget radio(String title, String value, VoidCallback onSelect) {
  return ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    trailing: Radio<String>(value: value),
    onTap: onSelect,
  );
}

Widget radioTts(
  BuildContext context,
  String title,
  TtsHighlightMode value,
  TtsHighlightMode groupValue,
  ValueChanged<TtsHighlightMode> onChanged,
) {
  return ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      value == groupValue
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked,
      color: value == groupValue
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      size: 20,
    ),
    title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
    onTap: () => onChanged(value),
  );
}
