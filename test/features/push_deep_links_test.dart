import 'package:buffet_app/data/push/push_deep_links.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

RemoteMessage _message({String? route}) => RemoteMessage(
  data: {
    'kind': 'OrderReady',
    'orderId': '412',
    if (route != null) 'route': route,
  },
);

void main() {
  group('a tapped notification', () {
    test('remembers the route the server decided', () {
      // The route comes from the payload rather than being reassembled here
      // from the kind — the routing table must not live in two places.
      final links = PushDeepLinks()..remember(_message(route: '/order/412'));

      expect(links.takeIf(sessionIsOpen: true), '/order/412');
    });

    test('ignores a payload with no route', () {
      final links = PushDeepLinks()..remember(_message());

      expect(links.hasPending, isFalse);
      expect(links.takeIf(sessionIsOpen: true), isNull);
    });

    test('ignores an empty route', () {
      final links = PushDeepLinks()..remember(_message(route: ''));

      expect(links.hasPending, isFalse);
    });
  });

  group('a tap that lands while the app is locked', () {
    test('is held rather than discarded', () {
      // The router's guard bounces every route while locked, so navigating
      // there would silently lose the link instead of deferring it.
      final links = PushDeepLinks()..remember(_message(route: '/order/412'));

      expect(links.takeIf(sessionIsOpen: false), isNull);
      expect(
        links.hasPending,
        isTrue,
        reason: 'the link must survive the gate',
      );
    });

    test('is honoured once the session opens', () {
      final links = PushDeepLinks()..remember(_message(route: '/order/412'));

      links.takeIf(sessionIsOpen: false);

      // The user unlocks and arrives exactly where the notification pointed,
      // which is the whole point of having tapped it.
      expect(links.takeIf(sessionIsOpen: true), '/order/412');
    });

    test('is consumed only once', () {
      final links = PushDeepLinks()..remember(_message(route: '/order/412'));

      expect(links.takeIf(sessionIsOpen: true), '/order/412');
      expect(
        links.takeIf(sessionIsOpen: true),
        isNull,
        reason: 'a drained link must not fire again on the next transition',
      );
    });
  });

  group('two notifications', () {
    test('the most recent tap wins', () {
      // If two drinks went ready, the tap the user actually made last is the
      // one they meant.
      final links = PushDeepLinks()
        ..remember(_message(route: '/order/1'))
        ..remember(_message(route: '/order/2'));

      expect(links.takeIf(sessionIsOpen: true), '/order/2');
    });
  });
}
