import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/api/api_config.dart';
import '../../data/models/order_models.dart';

/// Keeps looking at the user's orders for a short while after the app leaves
/// the foreground, so a drink turning Ready still chimes (decided 2026-09-27).
///
/// **Only where nothing else will announce it**: a device registered for push
/// hears Ready from the server, and a second, local alert would ring twice.
/// That leaves iOS (no push until APNs is funded) and an Android device whose
/// registration failed.
///
/// **The OS decides how long this really runs.** iOS suspends an app within
/// seconds of it leaving the screen; the app asks for background time as it
/// goes (`AppDelegate.swift`), which iOS grants for about half a minute. An
/// Android process is frozen soon after it is cached. [window] is the most
/// this will ever ask for, not what it will get: on iOS, a drink that takes
/// three minutes will usually not chime.
///
/// **Employees only**: it lives on Home, which staff never open, as the
/// foreground tracker always has.
///
/// One known double: a device the server still holds a token for, whose
/// registration this session failed, gets the push and this alert both.
///
/// It calls the server directly rather than refreshing a provider: a provider
/// refreshes on the next frame, and an app in the background draws none, so
/// an invalidated provider would wait until the user came back.
class BackgroundOrderWatch {
  BackgroundOrderWatch({
    required this.look,
    required this.onOrders,
    this.interval = ApiConfig.backgroundPollInterval,
    this.window = ApiConfig.backgroundWatchWindow,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Fetches the user's orders. A failure is skipped; the next look retries.
  final Future<List<OrderSummaryDto>> Function() look;

  /// Every list fetched, for the caller to compare and announce.
  final void Function(List<OrderSummaryDto>) onOrders;

  final Duration interval;
  final Duration window;
  final DateTime Function() _clock;

  Timer? _timer;
  DateTime? _until;
  bool _looking = false;

  bool get isWatching => _timer != null;

  /// Starts watching, if any of [orders] can still change. Once the last one
  /// settles, or [window] runs out, it stops by itself.
  void start(List<OrderSummaryDto> orders) {
    if (isWatching || !orders.any((o) => o.orderStatus.isLive)) return;
    _until = _clock().add(window);
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _until = null;
  }

  Future<void> _tick() async {
    final until = _until;
    if (until == null || _looking) return;
    if (!_clock().isBefore(until)) return stop();

    _looking = true;
    try {
      final orders = await look();
      if (!isWatching) return;
      onOrders(orders);
      if (!orders.any((o) => o.orderStatus.isLive)) stop();
    } on Object catch (error) {
      // Offline in a pocket is normal. The next look tries again, and the
      // screen reloads on return whatever happens here. Logged, so a fault in
      // announcing is not silent too.
      debugPrint('Background order look failed: $error');
    } finally {
      _looking = false;
    }
  }
}
