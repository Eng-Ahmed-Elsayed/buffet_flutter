import 'package:buffet_app/data/models/auth_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OrderStatus is compared by name, never by ordinal', () {
    test('parses every documented wire value', () {
      expect(OrderStatus.fromWire('Pending'), OrderStatus.pending);
      expect(OrderStatus.fromWire('InProgress'), OrderStatus.inProgress);
      expect(OrderStatus.fromWire('Ready'), OrderStatus.ready);
      expect(OrderStatus.fromWire('Completed'), OrderStatus.completed);
      expect(OrderStatus.fromWire('Cancelled'), OrderStatus.cancelled);
    });

    test('round-trips through the wire value', () {
      for (final status in OrderStatus.values) {
        expect(OrderStatus.fromWire(status.wire), status);
      }
    });

    test('declaration order does not encode the server ordinals — Ready is 4 '
        'server-side, so any code comparing integers would be wrong', () {
      // If someone ever "helpfully" reorders this enum to match the server,
      // this test does not break — but nothing else depends on the index
      // either, which is the actual protection. Asserting the wire strings
      // is what keeps the comparison honest.
      expect(OrderStatus.ready.wire, 'Ready');
      expect(OrderStatus.values.indexOf(OrderStatus.ready), isNot(4));
    });

    test('an unknown status falls back to pending rather than throwing', () {
      // A new server-side state must not crash a shipped client.
      expect(OrderStatus.fromWire('SomethingNew'), OrderStatus.pending);
      expect(OrderStatus.fromWire(''), OrderStatus.pending);
    });

    test('cancellation is offered on Pending only', () {
      expect(OrderStatus.pending.isCancellable, isTrue);
      expect(OrderStatus.inProgress.isCancellable, isFalse);
      expect(OrderStatus.ready.isCancellable, isFalse);
      expect(OrderStatus.completed.isCancellable, isFalse);
      expect(OrderStatus.cancelled.isCancellable, isFalse);
    });

    test('polling stops once an order leaves the live states', () {
      expect(OrderStatus.pending.isLive, isTrue);
      expect(OrderStatus.inProgress.isLive, isTrue);
      // Ready is not "live" for polling: the drink is made and the next change
      // is a human handing it over.
      expect(OrderStatus.ready.isLive, isFalse);
      expect(OrderStatus.completed.isLive, isFalse);
      expect(OrderStatus.cancelled.isLive, isFalse);
    });
  });

  group('OrderSummaryDto', () {
    OrderSummaryDto parse(String status) => OrderSummaryDto.fromJson({
      'orderId': 1,
      'status': status,
      'createdAtUtc': '2026-08-18T09:00:00Z',
      'readyAtUtc': null,
      'handledAtUtc': null,
      'locationText': 'الدور الثالث',
      'onBehalfOfName': null,
      'notes': '',
      'lines': <Map<String, dynamic>>[],
    });

    test('isReady mirrors the server-computed value, by name', () {
      expect(parse('Ready').isReady, isTrue);
      expect(parse('Completed').isReady, isFalse);
      expect(parse('Pending').isReady, isFalse);
    });

    test('timestamps parse as UTC', () {
      final order = parse('Pending');
      expect(order.createdAtUtc.isUtc, isTrue);
    });
  });

  group('UserRole', () {
    test('decides the landing screen', () {
      expect(UserRole.fromWire('Staff').startsOnQueue, isTrue);
      expect(UserRole.fromWire('Employee').startsOnQueue, isFalse);
      // An Admin lands on the catalogue — admin work stays on the web.
      expect(UserRole.fromWire('Admin').startsOnQueue, isFalse);
    });

    test('an unknown role falls back to the least-privileged view', () {
      expect(UserRole.fromWire('Superuser'), UserRole.employee);
    });
  });
}
