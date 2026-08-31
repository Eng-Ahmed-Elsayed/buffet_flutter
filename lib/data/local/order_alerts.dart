import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// Android channel ids.
///
/// **A channel's behaviour is immutable once a device has created it** — an app
/// update cannot raise its importance or give it a sound afterwards, only the
/// user can. So these are per-kind from the start: somebody who silences a
/// cancellation must still be woken for a ready drink, and there is no way to
/// split a combined channel later.
///
/// When push arrives these ids must match the server's `PushChannels`
/// constants exactly. A mismatch drops the notification into the default
/// channel at default importance, where it will not wake the device.
abstract final class AlertChannels {
  static const orderReady = 'order_ready';
  static const orderCancelled = 'order_cancelled';
}

/// Tells the user their drink is ready, on the device, without a server push.
///
/// This exists because push is not available on iOS — an Apple Developer
/// account is a paid prerequisite and there is no budget for one — and iPhone
/// is where the users who most need this actually are. A local notification
/// closes the part of the gap that can be closed for free: the app is open, or
/// merely backgrounded and still alive, and a poll has just seen the status
/// change. It fires with sound, so the phone face-down on a desk is still
/// heard.
///
/// **What it deliberately does not do** is fix the app being fully closed with
/// the process killed. Nothing running on the device can, because nothing is
/// running. That case needs a server push, and on iOS it needs APNs. Do not
/// reach for `WorkManager` to paper over it — `JobScheduler`, which it is built
/// on, does not run in Doze at all.
class OrderAlerts {
  OrderAlerts(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;

  /// Whether the user has actually granted permission.
  ///
  /// Denied is a normal outcome, not an error: the notification centre and the
  /// outstanding-order card still work, so the app must never treat this as a
  /// failure or nag about it.
  bool granted = false;

  /// Prepares channels and asks for permission.
  ///
  /// Safe to call more than once — later calls are cheap no-ops. Call it once
  /// the user is signed in, never at startup: asking a stranger for
  /// notification permission before they have seen what the app does is how a
  /// permission gets denied permanently.
  Future<void> initialise({
    required String readyChannelName,
    required String readyChannelDescription,
    required String cancelledChannelName,
    required String cancelledChannelDescription,
  }) async {
    if (_ready) return;

    // Marked done up front, whatever happens below. A second attempt would
    // re-throw the same way and re-prompt the user for nothing.
    _ready = true;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      // Requested explicitly below rather than here, so the prompt appears at a
      // moment we choose.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    try {
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin),
      );
    } on Object catch (error) {
      // No platform implementation — a test binding, a desktop build, anywhere
      // the plugin was never registered. Alerts are an enhancement over the
      // notification list and the outstanding-order card, so their absence must
      // never take a screen down with it.
      debugPrint('Local notifications are unavailable here: $error');
      return;
    }

    try {
      await _createChannelsAndAsk(
        readyChannelName: readyChannelName,
        readyChannelDescription: readyChannelDescription,
        cancelledChannelName: cancelledChannelName,
        cancelledChannelDescription: cancelledChannelDescription,
      );
    } on Object catch (error) {
      debugPrint('Could not prepare notification channels: $error');
    }
  }

  Future<void> _createChannelsAndAsk({
    required String readyChannelName,
    required String readyChannelDescription,
    required String cancelledChannelName,
    required String cancelledChannelDescription,
  }) async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          AlertChannels.orderReady,
          readyChannelName,
          description: readyChannelDescription,
          // The one alert worth interrupting for: the drink is on the counter
          // going cold.
          importance: Importance.max,
        ),
      );
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          AlertChannels.orderCancelled,
          cancelledChannelName,
          description: cancelledChannelDescription,
          // Unexpected and actionable, but not urgent — nobody is waiting on a
          // counter for it.
          importance: Importance.defaultImportance,
        ),
      );

      granted = await androidPlugin.requestNotificationsPermission() ?? false;
    }

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    if (iosPlugin != null) {
      granted =
          await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
  }

  /// Announces that an order is ready to collect.
  ///
  /// The notification id is the order id, so a second alert for the same drink
  /// replaces the first rather than stacking a duplicate.
  Future<void> orderReady({
    required int orderId,
    required String title,
    required String body,
  }) => _show(
    orderId: orderId,
    channelId: AlertChannels.orderReady,
    importance: Importance.max,
    priority: Priority.high,
    title: title,
    body: body,
  );

  Future<void> orderCancelled({
    required int orderId,
    required String title,
    required String body,
  }) => _show(
    orderId: orderId,
    channelId: AlertChannels.orderCancelled,
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    title: title,
    body: body,
  );

  Future<void> _show({
    required int orderId,
    required String channelId,
    required Importance importance,
    required Priority priority,
    required String title,
    required String body,
  }) async {
    if (!_ready || !granted) return;

    try {
      await _plugin.show(
        orderId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelId,
            importance: importance,
            priority: priority,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // The order id, so a tap can open the right drink once deep-linking is
        // wired with push.
        payload: '$orderId',
      );
    } on Object catch (error) {
      // Never allowed to break the caller. Failing to announce a drink is worth
      // much less than the screen that was about to render it, and this runs
      // inside a poll that must keep polling.
      debugPrint('Could not show an order alert: $error');
    }
  }
}

final orderAlertsProvider = Provider<OrderAlerts>(
  (ref) => OrderAlerts(FlutterLocalNotificationsPlugin()),
);

/// Creates the notification channels and asks for permission, with the channel
/// names in the caller's language.
///
/// Called from **both landing screens**. It used to live on the composer, which
/// is the screen an employee lands on but one a staff member only ever reaches
/// by pushing it from the queue — so staff had no channels and were never asked
/// for permission at all. A shared helper is what keeps the two landing screens
/// from drifting apart on this again.
///
/// Deliberately called after the first frame of a landing screen rather than at
/// startup: a permission prompt shown before the user has seen what the app
/// does is how a permission gets denied permanently.
Future<void> prepareOrderAlerts(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);

  return ref
      .read(orderAlertsProvider)
      .initialise(
        readyChannelName: l10n.channelReadyName,
        readyChannelDescription: l10n.channelReadyDescription,
        cancelledChannelName: l10n.channelCancelledName,
        cancelledChannelDescription: l10n.channelCancelledDescription,
      );
}
