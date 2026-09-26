import 'dart:async';

import 'package:buffet_app/app/routes.dart';
import 'package:buffet_app/data/local/order_alerts.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/push/push_deep_links.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/home/home_screen.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:buffet_app/features/order/order_status_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

OrderSummaryDto _order(int id, String status) => OrderSummaryDto(
  orderId: id,
  status: status,
  createdAtUtc: DateTime.utc(2026, 8, 20, 7),
  readyAtUtc: null,
  handledAtUtc: null,
  locationText: '',
  onBehalfOfName: null,
  notes: '',
  lines: const [],
);

/// Records the alerts instead of showing them.
class _RecordingAlerts extends OrderAlerts {
  _RecordingAlerts() : super(FlutterLocalNotificationsPlugin());

  final ready = <int>[];
  final cancelled = <int>[];

  @override
  Future<void> orderReady({
    required int orderId,
    required String title,
    required String body,
  }) async => ready.add(orderId);

  @override
  Future<void> orderCancelled({
    required int orderId,
    required String title,
    required String body,
  }) async => cancelled.add(orderId);
}

void main() {
  group('OrderStatusTracker', () {
    test('the first look only records', () {
      final tracker = OrderStatusTracker();
      expect(tracker.changed([_order(1, 'Ready')]), isEmpty);
    });

    test('a move to Ready or Cancelled is reported once', () {
      final tracker = OrderStatusTracker()
        ..changed([_order(1, 'InProgress'), _order(2, 'Pending')]);

      final changed = tracker.changed([
        _order(1, 'Ready'),
        _order(2, 'Cancelled'),
      ]);
      expect(changed.map((o) => o.orderId), [1, 2]);
      // Same statuses again: nothing new.
      expect(
        tracker.changed([_order(1, 'Ready'), _order(2, 'Cancelled')]),
        isEmpty,
      );
    });

    test('other moves and new orders are not news', () {
      final tracker = OrderStatusTracker()..changed([_order(1, 'Pending')]);
      expect(
        tracker.changed([_order(1, 'InProgress'), _order(3, 'Ready')]),
        isEmpty,
      );
    });

    test('after forget, the next look starts afresh', () {
      final tracker = OrderStatusTracker()
        ..changed([_order(1, 'InProgress')])
        ..forget();
      expect(tracker.changed([_order(1, 'Ready')]), isEmpty);
    });
  });

  group('Home announces an order turning Ready, from any look at the list', () {
    setUpAll(loadAppFonts);

    Future<(_RecordingAlerts, void Function(List<OrderSummaryDto>))> pump(
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final alerts = _RecordingAlerts();
      var orders = [_order(41, 'InProgress')];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderAlertsProvider.overrideWithValue(alerts),
            myOrdersProvider.overrideWith((ref) async => orders),
            catalogueProvider.overrideWith(
              (ref) async => const CatalogueResponse(
                drinks: [],
                sugars: [],
                extras: [],
                locations: [],
              ),
            ),
            favouritesProvider.overrideWith(
              (ref) async => const FavouritesResponse(favourites: []),
            ),
            canOrderForGuestsProvider.overrideWith((ref) => false),
            notificationsProvider.overrideWith((ref) async => const []),
          ],
          child: testApp(home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return (alerts, (List<OrderSummaryDto> next) => orders = next);
    }

    void refresh(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
            .invalidate(myOrdersProvider);

    testWidgets('a poll that sees Ready chimes', (tester) async {
      final (alerts, setOrders) = await pump(tester);

      setOrders([_order(41, 'Ready')]);
      refresh(tester);
      await tester.pumpAndSettle();

      expect(alerts.ready, [41]);
    });

    testWidgets('coming back to the app does not chime for what is on screen', (
      tester,
    ) async {
      final (alerts, setOrders) = await pump(tester);

      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      setOrders([_order(41, 'Ready')]);
      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();

      expect(alerts.ready, isEmpty);
    });

    testWidgets('a load that lands in the background is not the baseline', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final alerts = _RecordingAlerts();
      var orders = [_order(41, 'InProgress')];
      Completer<List<OrderSummaryDto>>? held;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderAlertsProvider.overrideWithValue(alerts),
            myOrdersProvider.overrideWith(
              (ref) => held?.future ?? Future.value(orders),
            ),
            catalogueProvider.overrideWith(
              (ref) async => const CatalogueResponse(
                drinks: [],
                sugars: [],
                extras: [],
                locations: [],
              ),
            ),
            favouritesProvider.overrideWith(
              (ref) async => const FavouritesResponse(favourites: []),
            ),
            canOrderForGuestsProvider.overrideWith((ref) => false),
            notificationsProvider.overrideWith((ref) async => const []),
          ],
          child: testApp(home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // A fetch starts in the foreground and is still in flight at lock time…
      held = Completer();
      refresh(tester);
      await tester.pump();
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      // …and lands while the app is in the background.
      final inFlight = held;
      held = null;
      inFlight.complete([_order(41, 'InProgress')]);
      await tester.pump();

      orders = [_order(41, 'Ready')];
      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();

      // On screen on return, and pushed already on Android: no chime.
      // Returning passes through `hidden`, which forgets as well; the resume
      // forget is the explicit backstop. This pins the outcome either way.
      expect(alerts.ready, isEmpty);
    });
  });

  group('a tapped alert opens its order', () {
    test('the route is held like a tapped push', () {
      final links = PushDeepLinks()..rememberRoute(Routes.orderStatusFor(41));
      // Held at the lock screen, honoured once the session is open.
      expect(links.takeIf(sessionIsOpen: false), isNull);
      expect(links.takeIf(sessionIsOpen: true), Routes.orderStatusFor(41));
    });
  });
}
