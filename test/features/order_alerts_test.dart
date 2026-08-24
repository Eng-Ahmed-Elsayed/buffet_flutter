import 'package:buffet_app/data/local/order_alerts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The plugin is a factory singleton and cannot be subclassed, so these cover
  // the guards that keep it from being reached at all. What actually appears in
  // the tray is a physical-device check — see the verification list in
  // docs/firebase-setup-checklist.md.
  group('OrderAlerts stays silent unless it may speak', () {
    test('before it has been initialised', () async {
      // Guards the poll: a status change arriving before the permission prompt
      // has been answered must not throw inside a timer callback, and must not
      // reach the plugin.
      final alerts = OrderAlerts(FlutterLocalNotificationsPlugin());

      await alerts.orderReady(orderId: 412, title: 'جاهز', body: 'تفضل');
      await alerts.orderCancelled(orderId: 412, title: 'ملغى', body: 'عذرًا');

      expect(alerts.granted, isFalse);
    });

    test('when permission was refused', () async {
      // Denial is a normal outcome, not an error. The notification list and the
      // outstanding-order card carry the information regardless, so nothing
      // here may throw or nag.
      final alerts = OrderAlerts(FlutterLocalNotificationsPlugin())
        ..granted = false;

      await alerts.orderReady(orderId: 412, title: 'جاهز', body: 'تفضل');

      expect(alerts.granted, isFalse);
    });
  });

  group('channel ids', () {
    test('match the ids the server will send with a push', () {
      // A mismatch drops a push into the default channel at default
      // importance, where it does not wake the device — and the failure is
      // silent, which is why this is pinned rather than left to review.
      expect(AlertChannels.orderReady, 'order_ready');
      expect(AlertChannels.orderCancelled, 'order_cancelled');
    });

    test('ready and cancelled are separate', () {
      // Per-kind because a channel's behaviour is immutable once created:
      // somebody who silences cancellations must still be woken for a drink,
      // and a combined channel could never be split afterwards.
      expect(AlertChannels.orderReady, isNot(AlertChannels.orderCancelled));
    });
  });
}
