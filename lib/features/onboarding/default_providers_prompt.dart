import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_prefs.dart';
import '../../core/providers/registries.dart';
import '../../router/root_navigator.dart';
import '../../theme/tokens.dart';
import '../../widgets/add_default_providers_button.dart';

/// Set once the first-launch prompt has been answered (either way), so it is
/// asked exactly once per install and never again on later launches.
const kDefaultProvidersPromptShownKey = 'onboarding.default_pviders_shown';

/// Offer the default providers on first launch, if the app has none.
///
/// Deliberately an *offer*, not an automatic add: a fresh install downloads and
/// executes provider JS, and that only happens after the user says yes. Skipped
/// entirely when the app already has registries (returning user, or an import),
/// and the empty states keep offering the same one-click add afterwards.
///
/// Safe to call before the first frame resolves a navigator: it reads the root
/// navigator context, and returns quietly when there is not one yet.
Future<void> maybePromptDefaultProviders(WidgetRef ref) async {
  final prefs = ref.read(appPrefsProvider);
  if (prefs.getBool(kDefaultProvidersPromptShownKey) ?? false) return;

  // Recorded before the dialog, so a failed/cancelled prompt can never turn
  // into an every-launch nag. The user can still add defaults later from any
  // empty provider state.
  await prefs.setBool(kDefaultProvidersPromptShownKey, true);

  // Await the load rather than reading `.value`: on a cold start the list is
  // still loading, and its empty default state is not evidence of "no
  // registries" — it would prompt users who already added some.
  final registries = await ref.read(registriesProvider.future);
  if (registries.isNotEmpty) return;

  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;

  await showDialog<void>(
    context: ctx,
    builder: (_) => const _DefaultProvidersPromptDialog(),
  );
}

class _DefaultProvidersPromptDialog extends ConsumerStatefulWidget {
  const _DefaultProvidersPromptDialog();

  @override
  ConsumerState<_DefaultProvidersPromptDialog> createState() =>
      _DefaultProvidersPromptDialogState();
}

class _DefaultProvidersPromptDialogState
    extends ConsumerState<_DefaultProvidersPromptDialog> {
  @override
  Widget build(BuildContext context) {
    // The button adds the registry and the list updates; this closes the
    // prompt as soon as there is something to show, so a success is not left
    // sitting behind a dismissed-by-hand dialog.
    ref.listen(registriesProvider, (_, next) {
      if ((next.value ?? const []).isNotEmpty && mounted) {
        Navigator.of(context).pop();
      }
    });

    return AlertDialog(
      title: const Text('Add sources to get started'),
      content: Text(
        'NovelDock reads novels through source extensions, so it starts '
        'with none. Add the official set now, or pick individual sources '
        'later from the Catalog tab.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        const Padding(
          padding: EdgeInsets.only(right: Insets.md),
          child: AddDefaultProvidersButton(),
        ),
      ],
    );
  }
}
