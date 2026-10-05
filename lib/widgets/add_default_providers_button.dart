import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/registries.dart';

/// One-click "add the default providers" action.
///
/// Self-hides once the default registry is in the user's list, so an empty
/// provider state stops offering it the moment it is no longer needed and no
/// call site has to re-check. Reports through a snackbar because this is
/// network work that can fail (offline, 404, blocked) and a button that
/// silently does nothing is worse than no button.
class AddDefaultProvidersButton extends ConsumerStatefulWidget {
  /// Stretch to the width of its parent instead of hugging the label.
  final bool expanded;

  const AddDefaultProvidersButton({super.key, this.expanded = false});

  @override
  ConsumerState<AddDefaultProvidersButton> createState() =>
      _AddDefaultProvidersButtonState();
}

class _AddDefaultProvidersButtonState
    extends ConsumerState<AddDefaultProvidersButton> {
  bool _adding = false;

  Future<void> _add() async {
    setState(() => _adding = true);
    // The ProviderContainer, not this widget's ref: the download outlives the
    // tap and must not be cancelled if the screen is disposed mid-flight.
    final error = await addDefaultRegistry(ref.container);
    if (!mounted) return;
    setState(() => _adding = false);

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      error == null
          ? const SnackBar(
              content: Text('Default providers added — find them in Catalog'),
            )
          : SnackBar(content: Text('Could not add defaults: $error')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final registries = ref.watch(registriesProvider).value ?? const [];
    if (hasDefaultRegistry(registries)) return const SizedBox.shrink();

    final button = FilledButton.icon(
      onPressed: _adding ? null : _add,
      icon: _adding
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome, size: 18),
      label: Text(_adding ? 'Adding...' : 'Add default providers'),
    );
    return widget.expanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}
