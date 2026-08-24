import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Holds where a tapped notification should send the user, until it is safe to go.
///
/// Two things make this less trivial than a `go()` call.
///
/// The route arrives from the message's `route` data key, decided server-side,
/// rather than being reassembled here from the notification kind — the routing
/// table must not live in two places.
///
/// And a tap can land while the app is at the biometric lock or the forced
/// password change. The router's guard deliberately bounces every route in those
/// stages so a deep link cannot walk around the gate, which means navigating
/// there would silently *discard* the link rather than defer it. So it is held,
/// and drained once the session is genuinely open — the user unlocks and arrives
/// exactly where the notification pointed, which is the whole point of tapping
/// it.
class PushDeepLinks {
  String? _pending;

  /// Whether a link is waiting to be honoured.
  bool get hasPending => _pending != null;

  /// Records a link to follow. Replaces any earlier one: if two drinks went
  /// ready, the tap the user actually made is the one they meant.
  void remember(RemoteMessage message) {
    final route = message.data['route'];
    if (route is String && route.isNotEmpty) _pending = route;
  }

  /// Takes the pending link, if the session is open enough to honour it.
  ///
  /// Returns null — and **keeps** the link — when it is not, so a later call
  /// after unlocking still finds it.
  String? takeIf({required bool sessionIsOpen}) {
    if (!sessionIsOpen) return null;
    final route = _pending;
    _pending = null;
    return route;
  }

  /// Wires the three ways a tap can reach a running app.
  ///
  /// Both terminated and background are needed: they cover different states and
  /// neither substitutes for the other.
  Future<void> listen({required void Function() onLink}) async {
    try {
      // Terminated: the message that launched the app. Consulted once, here,
      // rather than in main() — where the router does not exist yet and the
      // auth stage is still `restoring`.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        remember(initial);
        onLink();
      }

      // Backgrounded but alive.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        remember(message);
        onLink();
      });
    } on Object catch (error) {
      debugPrint('Could not listen for notification taps: $error');
    }
  }
}
