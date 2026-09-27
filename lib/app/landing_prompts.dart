import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/order_alerts.dart';
import '../data/push/push_controller.dart';
import '../features/auth/auth_controller.dart';
import '../l10n/app_localizations.dart';
import '../theme/motion.dart';

/// Creates the alert channels, asks for notification permission, and
/// registers for push — **one question at a time**.
///
/// On a first landing three used to arrive at once: the biometric offer, the
/// local-alert permission and push's own request for the same permission.
/// Now the biometric offer is answered first, then the one permission dialog
/// is shown, and push registers after it, finding the permission answered.
///
/// Called from **both landing screens**. It used to live on the composer, which
/// is the screen an employee lands on but one a staff member only ever reaches
/// by pushing it from the queue — so staff had no channels and were never asked
/// for permission at all. A shared helper is what keeps the two landing screens
/// from drifting apart on this again.
///
/// Deliberately called after the first frame of a landing screen rather than at
/// startup: a permission prompt shown before the user has seen what the app
/// does is how a permission gets denied permanently. Idempotent, so it runs on
/// every landing, which is every sign-in and unlock.
Future<void> prepareLandingPrompts(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);

  final offered = ref.read(authControllerProvider).offerBiometricEnrolment;
  await _biometricOfferSettled(ref);
  if (!context.mounted) return;
  // The offer is answered the moment its button is pressed, before its sheet
  // has closed. A permission dialog opened then paused the app with the sheet
  // still on screen, and it stayed there after the dialog: seen on the
  // emulator 2026-09-27. So the sheet is let go first.
  if (offered) {
    await Future<void>.delayed(Motion.of(context, Motion.sheetExit));
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
  }

  await ref
      .read(orderAlertsProvider)
      .initialise(
        readyChannelName: l10n.channelReadyName,
        readyChannelDescription: l10n.channelReadyDescription,
        cancelledChannelName: l10n.channelCancelledName,
        cancelledChannelDescription: l10n.channelCancelledDescription,
      );
  if (!context.mounted) return;

  await ref.read(pushControllerProvider).register();
}

/// Completes once no biometric offer is standing.
Future<void> _biometricOfferSettled(WidgetRef ref) {
  if (!ref.read(authControllerProvider).offerBiometricEnrolment) {
    return Future.value();
  }
  final settled = Completer<void>();
  late final ProviderSubscription<bool> subscription;
  subscription = ref.listenManual<bool>(
    authControllerProvider.select((s) => s.offerBiometricEnrolment),
    (_, offering) {
      if (offering || settled.isCompleted) return;
      settled.complete();
      subscription.close();
    },
  );
  return settled.future;
}
