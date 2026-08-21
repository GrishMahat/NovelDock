import 'package:flutter/material.dart';

class StatusPickerSheet extends StatefulWidget {
  const StatusPickerSheet({super.key});

  @override
  State<StatusPickerSheet> createState() => _StatusPickerSheetState();
}

class _StatusPickerSheetState extends State<StatusPickerSheet> {
  String _selected = 'Reading';

  static const _options = [
    'Reading',
    'On Hold',
    'Plan to Read',
    'Completed',
    'Dropped',
  ];

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
            'Add to Library',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._options.map(
            (s) => ListTile(
              title: Text(s),
              trailing: _selected == s
                  ? const Icon(Icons.check, size: 20)
                  : null,
              onTap: () => setState(() => _selected = s),
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.remove_circle, color: Colors.red.shade400),
            title: Text('None', style: TextStyle(color: Colors.red.shade400)),
            trailing: _selected == 'None'
                ? Icon(Icons.check, size: 20, color: Colors.red.shade400)
                : null,
            onTap: () => setState(() => _selected = 'None'),
          ),
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
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('OK'),
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
