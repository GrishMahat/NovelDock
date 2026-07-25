import 'package:flutter/material.dart';

import '../../../core/tts/tts_manager.dart';
import '../../../theme/app_theme.dart';

Widget section(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.kPrimary)),
  );
}

Widget tile({required String title, String? subtitle, VoidCallback? onTap}) {
  return ListTile(
    dense: true, contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 12)) : null,
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}

Widget slider(String label, double value, double min, double max, String display, ValueChanged<double> onChanged) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13))),
      Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
      SizedBox(width: 50, child: Text(display, style: const TextStyle(fontSize: 12))),
    ]),
  );
}

Widget switchTile(String title, String? subtitle, bool value, ValueChanged<bool> onChanged) {
  return SwitchListTile(
    dense: true, contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(fontSize: 11)) : null,
    value: value,
    onChanged: onChanged,
  );
}

Widget radio(String title, String value, String groupValue, ValueChanged<String?> onChanged) {
  return RadioListTile<String>(
    dense: true, contentPadding: EdgeInsets.zero,
    title: Text(title), value: value, groupValue: groupValue, onChanged: onChanged,
  );
}

Widget radioTts(String title, TtsHighlightMode value, TtsHighlightMode groupValue, ValueChanged<TtsHighlightMode> onChanged) {
  return ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      value == groupValue ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      color: value == groupValue ? AppTheme.kPrimary : AppTheme.kTextSecondaryDark,
      size: 20,
    ),
    title: Text(title, style: const TextStyle(fontSize: 14)),
    onTap: () => onChanged(value),
  );
}
