import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
///
/// One screen is *both*, depending on how it was reached: the composer is the
/// employee's landing screen, but staff reach it by `push` from the queue. So
/// the guard checks the stack at back-press time rather than trusting the
/// wrapping — with something to pop to, it steps aside and lets the ordinary
/// pop happen.
class ExitConfirmation extends StatelessWidget {
  const ExitConfirmation({super.key, required this.child, this.onExit});

  final Widget child;

  /// What actually closes the app. Overridden in tests, which cannot observe
  /// `SystemNavigator.pop()` and do not run on Android.
  ///
  /// Injected rather than left implicit because the real one was wrong for
  /// months and no test could reach it — the confirmation dialog appeared,
  /// the user tapped "exit", and nothing happened.
  final Future<void> Function()? onExit;

  @override
  Widget build(BuildContext context) {
    // With a route beneath this one, back is an ordinary pop and there is
    // nothing to confirm — `canPop: true` hands the gesture straight to the
    // Navigator. Read here rather than in onPopInvoked because PopScope needs
    // the answer before the gesture arrives.
    final hasRouteBeneath = Navigator.of(context).canPop();

    return PopScope(
      // Never pops on its own when this really is a landing screen: the
      // callback decides, so the confirmation can be shown before anything
      // closes.
      canPop: hasRouteBeneath,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final shouldExit = await _confirm(context);
        if (!shouldExit) return;

        // SystemNavigator.pop(), NOT Navigator.maybePop().
        //
        // This is a landing screen: its route is the ROOT, so there is nothing
        // for the Navigator to pop to — and `canPop: false` above is still
        // intercepting, so maybePop() asks this very PopScope and is refused.
        // The app stayed open and the confirmation did nothing.
        //
        // Android only. On iOS an app terminating itself is against the HIG
        // and the call is a no-op there anyway, so the guard says so plainly
        // rather than relying on that.
        await (onExit ?? _systemExit)();
      },
      child: child,
    );
  }

  static Future<void> _systemExit() async {
    if (Platform.isAndroid) await SystemNavigator.pop();
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
