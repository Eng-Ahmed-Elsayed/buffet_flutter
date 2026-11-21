import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/preferences_store.dart';

/// Which queue orders are new since the last look.
///
/// Remembers every id it has been shown, so an order is announced once at
/// most: a refresh dropped as stale (`_mutationEpoch`) never reaches here, and
/// the one after it finds the same ids already seen. An order that leaves the
/// queue and comes back (a failed serve put back) is not new either.
class NewOrderDetector {
  Set<int>? _seen;

  /// Records [ids] and returns those not seen before.
  ///
  /// Nothing is new on the first look, which is the queue as it already was,
  /// nor on a [silent] one: the catch-up after the app returns to the screen,
  /// where the person looking at the list is the one who would be alerted.
  List<int> observe(Iterable<int> ids, {bool silent = false}) {
    final seen = _seen;
    final current = ids.toSet();
    if (seen == null) {
      _seen = current;
      return const [];
    }
    final fresh = [
      for (final id in current)
        if (!seen.contains(id)) id,
    ];
    seen.addAll(current);
    return silent ? const [] : fresh;
  }
}

/// Orders this device placed itself. A staff member's own order is served in
/// the same call and rarely reaches the queue, but one that does (a retry
/// matched as a duplicate, a serve that failed) must not alert the person who
/// has just ordered it.
final selfPlacedOrdersProvider = Provider<Set<int>>((ref) => <int>{});

/// Whether the queue sounds and vibrates for new orders. Null while the
/// stored setting loads, which callers read as on: it is the default.
class QueueAlertsSetting extends StateNotifier<bool?> {
  QueueAlertsSetting(this._preferences) : super(null) {
    unawaited(_load());
  }

  final PreferencesStore _preferences;

  Future<void> _load() async {
    try {
      final enabled = await _preferences.readQueueAlertsEnabled();
      if (mounted && state == null) state = enabled;
    } on Object catch (error) {
      // Storage failing leaves the default, which is on.
      debugPrint('Could not read the queue alert setting: $error');
      if (mounted && state == null) state = true;
    }
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    try {
      await _preferences.writeQueueAlertsEnabled(enabled);
    } on Object catch (error) {
      debugPrint('Could not save the queue alert setting: $error');
    }
  }
}

final queueAlertsSettingProvider =
    StateNotifierProvider<QueueAlertsSetting, bool?>(
      (ref) => QueueAlertsSetting(ref.watch(preferencesStoreProvider)),
    );
