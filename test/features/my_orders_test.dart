import 'package:buffet_app/data/models/order_models.dart';
import 'package:flutter_test/flutter_test.dart';

OrderSummaryDto order(int id, String status) => OrderSummaryDto.fromJson({
  'orderId': id,
  'status': status,
  'createdAtUtc': '2026-08-19T08:12:53.1082129Z',
  'readyAtUtc': null,
  'handledAtUtc': null,
  'locationText': 'مكتبي',
  'onBehalfOfName': null,
  'notes': '',
  'lines': <dynamic>[],
});

void main() {
  group('order history grouping — status read by name, never ordinal', () {
    test('Ready is live but is NOT isLive — it needs its own handling', () {
      // The trap: Ready = 4 sits out of workflow order, so any ordinal
      // comparison breaks. isLive covers Pending and InProgress only, which
      // is why the screen lists Ready separately rather than assuming.
      expect(OrderStatus.ready.isLive, isFalse);
      expect(OrderStatus.pending.isLive, isTrue);
      expect(OrderStatus.inProgress.isLive, isTrue);
      expect(OrderStatus.completed.isLive, isFalse);
      expect(OrderStatus.cancelled.isLive, isFalse);
    });

    test('a live order is separable from a finished one', () {
      // The whole point of the screen: a drink still being made must be
      // reachable after leaving the tracking screen.
      final all = [
        order(41, 'Completed'),
        order(42, 'Pending'),
        order(43, 'Ready'),
        order(44, 'Cancelled'),
        order(45, 'InProgress'),
      ];

      final live = all.where((o) => o.orderStatus.isLive).toList();
      final ready = all
          .where((o) => o.orderStatus == OrderStatus.ready)
          .toList();
      final past = all
          .where(
            (o) => !o.orderStatus.isLive && o.orderStatus != OrderStatus.ready,
          )
          .toList();

      expect(live.map((o) => o.orderId), [42, 45]);
      expect(ready.map((o) => o.orderId), [43]);
      expect(past.map((o) => o.orderId), [41, 44]);
      // Nothing is lost between the three buckets.
      expect(live.length + ready.length + past.length, all.length);
    });

    test('Ready sorts ahead of the rest — a waiting drink is most urgent', () {
      final all = [order(42, 'Pending'), order(43, 'Ready')];
      final live = all.where((o) => o.orderStatus.isLive).toList();
      final ready = all
          .where((o) => o.orderStatus == OrderStatus.ready)
          .toList();

      expect([...ready, ...live].map((o) => o.orderId), [43, 42]);
    });

    test('an unrecognised status does not crash the list', () {
      // fromWire falls back to pending rather than throwing, so a status the
      // client has not seen still renders as a live order.
      expect(order(46, 'SomethingNew').orderStatus, OrderStatus.pending);
    });

    test('createdAtUtc parses as UTC so it can be converted for display', () {
      expect(order(41, 'Completed').createdAtUtc.isUtc, isTrue);
    });
  });
}
