import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/brand_colors.dart';

/// Asks before letting the system back gesture close the app.
///
/// Wraps a **landing** screen only — the catalogue and the staff queue, which
/// have nothing beneath them in the navigation stack. Without this, back from
/// either one closes the app outright, which is a poor way to lose a
/// half-composed order or to leave a queue someone is working.
///
/// Screens reached by `push` are deliberately **not** wrapped: they have
/// somewhere to go back to, and asking there would be an obstacle rather than
/// a safeguard.
class ExitConfirmation extends StatelessWidget {
  const ExitConfirmation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Never pops on its own: the callback decides, so the confirmation can
      // be shown before anything closes.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldExit = await _confirm(context);
        // Popping the root route is what actually closes the app. Navigator
        // handles it rather than SystemNavigator.pop() so iOS — where killing
        // your own app is against the HIG — simply does nothing.
        if (shouldExit && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: child,
    );
  }

  Future<bool> _confirm(BuildContext context) async {
    final l10n = AppLocalizations.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.exitAppTitle),
        content: Text(l10n.exitAppBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: BrandColors.danger),
            child: Text(l10n.exitAppConfirm),
          ),
        ],
      ),
    );

    // Dismissing the dialog is a "no": staying is always the safe default.
    return result ?? false;
  }
}
