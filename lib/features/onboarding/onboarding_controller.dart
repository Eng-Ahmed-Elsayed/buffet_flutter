import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/preferences_store.dart';
import '../auth/auth_controller.dart';

/// Whether the first-launch explainer has been seen on this device.
///
/// `null` while the flag is still being read, so the router can hold on the
/// splash rather than flash the explainer at someone who has already seen it.
///
/// Kept out of `AuthState` on purpose: that state is rebuilt field by field in
/// many places, and a flag carried through all of them is a flag one of them
/// eventually drops.
class OnboardingController extends StateNotifier<bool?> {
  OnboardingController(this._preferences) : super(null) {
    unawaited(_restore());
  }

  final PreferencesStore _preferences;

  Future<void> _restore() async {
    try {
      final seen = await _preferences.readOnboardingSeen();
      if (mounted && state == null) state = seen;
    } on Exception {
      // Storage unavailable: show nothing rather than hold the app on the
      // splash. Skipping an explainer costs nothing; a stuck splash is fatal.
      if (mounted && state == null) state = true;
    }
  }

  /// Called from Skip, Sign in and the last slide. The router moves on as
  /// soon as the state changes, so the write is not awaited by the caller.
  Future<void> markSeen() async {
    if (state == true) return;
    state = true;
    await _preferences.writeOnboardingSeen();
  }
}

/// Any session — signed in, locked, or stuck on the forced password change —
/// means this person already uses the app, so the explainer is marked seen.
///
/// Without this, everyone who signed in before the explainer existed has no
/// flag, and the moment their session ends (a 401, sign-out, "use password
/// instead") they would be sent through three slides before the sign-in
/// screen that explains their session expired.
final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, bool?>((ref) {
      final controller = OnboardingController(
        ref.watch(preferencesStoreProvider),
      );
      ref.listen<AuthStage>(authStageProvider, (_, stage) {
        if (stage != AuthStage.restoring && stage != AuthStage.signedOut) {
          unawaited(controller.markSeen());
        }
      }, fireImmediately: true);
      // Signed out but not new: seen on a device where the session expired
      // before this flag existed, which sent a returning user through three
      // slides with the "session expired" notice behind them.
      ref.listen<bool>(hasUsedAppProvider, (_, used) {
        if (used) unawaited(controller.markSeen());
      }, fireImmediately: true);
      return controller;
    });
