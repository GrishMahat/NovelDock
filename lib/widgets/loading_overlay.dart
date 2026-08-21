import 'package:flutter/material.dart';

/// Reusable loading overlay widget.
class LoadingOverlay extends StatelessWidget {
  final String? message;
  const LoadingOverlay({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline loading indicator for lists.
Widget buildListLoading() => const Center(
  child: Padding(
    padding: EdgeInsets.all(32),
    child: CircularProgressIndicator(),
  ),
);

/// Inline loading indicator for small areas.
Widget buildSmallLoading() => const SizedBox(
  width: 24,
  height: 24,
  child: CircularProgressIndicator(strokeWidth: 2),
);
