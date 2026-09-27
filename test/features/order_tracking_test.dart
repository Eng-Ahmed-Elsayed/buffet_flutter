import 'package:buffet_app/data/local/order_alerts.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/repositories/order_repository.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:buffet_app/features/order/order_status_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/app_harness.dart';

final _l10n = lookupAppLocalizations(const Locale('ar'));

OrderLineDto _line(String drink, {int id = 1}) => OrderLineDto(
  drinkItemId: id,
  drinkNameAr: drink,
  sugarSpoons: 1,
  variantId: null,
  sugarItemId: null,
  extraItemIds: const [],
  lineNote: null,
  drinkFromOwn: false,
  sugarFromOwn: false,
  ownExtraItemIds: const [],
);

OrderSummaryDto _order(
  int id,
  String status, {
  List<OrderLineDto>? lines,
  DateTime? readyAtUtc,
  DateTime? handledAtUtc,
  DateTime? startedAtUtc,
  String? fulfilment,
}) => OrderSummaryDto(
  orderId: id,
  status: status,
  createdAtUtc: DateTime.utc(2026, 8, 20, 7),
  readyAtUtc: readyAtUtc,
  handledAtUtc: handledAtUtc,
  locationText: 'مكتبي',
  onBehalfOfName: null,
  notes: '',
  lines: lines ?? [_line('قهوة')],
  startedAtUtc: startedAtUtc,
  fulfilment: fulfilment,
);

const _menu = CatalogueResponse(
  drinks: [
    CatalogueItemDto(
      itemId: 1,
      nameAr: 'قهوة',
      nameEn: 'Coffee',
      category: 'Drink',
      unit: 'ج',
      imageUrl: null,
      inStock: true,
      hasOwnStock: false,
      ownServingsLeft: 0,
      variants: [],
      allowedExtraItemIds: null,
    ),
  ],
  sugars: [],
  extras: [],
  locations: [],
);

Future<void> _pumpOrders(
  WidgetTester tester,
  List<OrderSummaryDto> orders, {
  Locale locale = const Locale('ar'),
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myOrdersProvider.overrideWith((ref) async => orders),
        favouritesProvider.overrideWith(
          (ref) async => const FavouritesResponse(favourites: []),
        ),
        catalogueProvider.overrideWith((ref) async => _menu),
      ],
      child: testApp(home: const MyOrdersScreen(), locale: locale),
    ),
  );
  await tester.pumpAndSettle();
}

class _OneOrderRepo implements OrderRepository {
  _OneOrderRepo(this.order);

  OrderSummaryDto order;
  int collected = 0;

  @override
  Future<OrderSummaryDto> fetchOrder({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async => order;

  /// "I picked it up": the server completes the order (§7.8).
  @override
  Future<void> confirmCollected({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    collected++;
    order = _order(
      order.orderId,
      'Completed',
      readyAtUtc: order.readyAtUtc,
      handledAtUtc: DateTime.utc(2026, 8, 20, 7, 9),
      fulfilment: order.fulfilment,
    );
  }

  @override
  Future<List<OrderSummaryDto>> fetchMyOrders({
    required String languageCode,
    required String networkErrorFallback,
  }) async => [order];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The status screen calls `context.canPop()`, so it needs a router above it.
/// Built in build, never at file load (CLAUDE.md).
class _RoutedStatus extends StatelessWidget {
  const _RoutedStatus();

  @override
  Widget build(BuildContext context) => Router.withConfig(
    config: GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => const OrderStatusScreen(orderId: 41),
        ),
      ],
    ),
  );
}

Future<_OneOrderRepo> _pumpStatus(
  WidgetTester tester,
  OrderSummaryDto order, {
  List<CatalogueItemDto> extras = const [],
}) async {
  final repository = _OneOrderRepo(order);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderRepositoryProvider.overrideWithValue(repository),
        catalogueProvider.overrideWith(
          (r) async => CatalogueResponse(
            drinks: const [],
            sugars: const [],
            extras: extras,
            locations: const [],
          ),
        ),
      ],
      child: testApp(home: const _RoutedStatus()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return repository;
}

void main() {
  group('the Orders tab splits what is on its way from what is finished', () {
    testWidgets('a live order is under In progress, a finished one under '
        'Earlier', (tester) async {
      await _pumpOrders(tester, [
        _order(41, 'Completed', lines: [_line('شاي', id: 2)]),
        _order(42, 'Pending', lines: [_line('قهوة')]),
      ]);

      expect(find.textContaining('قهوة'), findsOneWidget);
      expect(find.textContaining('شاي'), findsNothing);

      await tester.tap(find.text(_l10n.pastOrders));
      await tester.pumpAndSettle();

      expect(find.textContaining('شاي'), findsOneWidget);
      expect(find.textContaining('قهوة'), findsNothing);
    });

    testWidgets('Ready counts as in progress — the order has not stopped', (
      tester,
    ) async {
      await _pumpOrders(tester, [_order(43, 'Ready')]);

      expect(find.text(_l10n.statusReady), findsOneWidget);
    });

    testWidgets('an empty tab says which list is empty, not "no orders"', (
      tester,
    ) async {
      await _pumpOrders(tester, [_order(41, 'Completed')]);

      expect(find.text(_l10n.noLiveOrders), findsOneWidget);
      expect(find.text(_l10n.noOrdersTitle), findsNothing);
    });

    testWidgets('no orders at all reads as a first-time state', (tester) async {
      await _pumpOrders(tester, []);

      expect(find.text(_l10n.noOrdersTitle), findsOneWidget);
    });

    testWidgets('a row names its drinks, identical cups once with ×N', (
      tester,
    ) async {
      await _pumpOrders(tester, [
        _order(42, 'Pending', lines: [_line('قهوة'), _line('قهوة')]),
      ]);

      expect(find.textContaining('×2'), findsOneWidget);
      // The place moves beneath, beside the time.
      expect(find.textContaining('مكتبي'), findsOneWidget);
    });

    testWidgets('in English the drinks are named in English, as on the order '
        'they open', (tester) async {
      // The order stores only the Arabic name; the row must not show it to an
      // English reader when the status screen it opens says "Coffee".
      await _pumpOrders(tester, [
        _order(42, 'Pending', lines: [_line('قهوة'), _line('قهوة')]),
      ], locale: const Locale('en'));

      expect(find.textContaining('Coffee'), findsOneWidget);
      expect(find.textContaining('×2'), findsOneWidget);
      expect(find.textContaining('قهوة'), findsNothing);
    });
  });

  group('the tracking timeline', () {
    testWidgets('shows every step, with the times the API has', (tester) async {
      final ready = DateTime.utc(2026, 8, 20, 7, 5);
      final handled = DateTime.utc(2026, 8, 20, 7, 9);
      await _pumpStatus(
        tester,
        _order(41, 'Completed', readyAtUtc: ready, handledAtUtc: handled),
      );

      expect(find.text(_l10n.timelineSent), findsOneWidget);
      expect(find.text(_l10n.statusInProgress), findsOneWidget);
      expect(find.text(_l10n.statusReady), findsOneWidget);
      // Another day, so the date comes with the time.
      expect(find.text(Formatters.dateTime(ready, 'ar')), findsOneWidget);
      expect(find.text(Formatters.dateTime(handled, 'ar')), findsOneWidget);
    });

    testWidgets('being prepared carries the time staff started it', (
      tester,
    ) async {
      final started = DateTime.utc(2026, 8, 20, 7, 2);
      await _pumpStatus(
        tester,
        _order(41, 'InProgress', startedAtUtc: started),
      );
      expect(find.text(Formatters.dateTime(started, 'ar')), findsOneWidget);
    });

    testWidgets('served straight from Pending, the step is passed without a '
        'time', (tester) async {
      // startedAtUtc is never backfilled (§7.3).
      final ready = DateTime.utc(2026, 8, 20, 7, 5);
      await _pumpStatus(tester, _order(41, 'Ready', readyAtUtc: ready));
      expect(find.text(_l10n.statusInProgress), findsOneWidget);
      expect(find.text(Formatters.dateTime(ready, 'ar')), findsOneWidget);
    });

    testWidgets('a cancelled order stops after Sent', (tester) async {
      await _pumpStatus(tester, _order(41, 'Cancelled'));

      expect(find.text(_l10n.timelineSent), findsOneWidget);
      expect(find.text(_l10n.statusCancelled), findsWidgets);
      // Never shown as if it were still going to be made.
      expect(find.text(_l10n.statusInProgress), findsNothing);
      expect(find.text(_l10n.statusReady), findsNothing);
    });

    testWidgets('Ready always carries its word, never colour alone', (
      tester,
    ) async {
      await _pumpStatus(
        tester,
        _order(41, 'Ready', readyAtUtc: DateTime.utc(2026, 8, 20, 7, 5)),
      );

      expect(find.text(_l10n.statusReady), findsWidgets);
      expect(find.text(_l10n.readyBody), findsOneWidget);
    });
  });

  group('Ready follows how the order reaches the person (§7.8)', () {
    final ready = DateTime.utc(2026, 8, 20, 7, 5);

    testWidgets('a pickup says to collect it, and the employee can close it', (
      tester,
    ) async {
      final repository = await _pumpStatus(
        tester,
        _order(41, 'Ready', readyAtUtc: ready, fulfilment: 'Pickup'),
      );
      expect(find.text(_l10n.readyBodyPickup), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text(_l10n.pickedItUp),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(_l10n.pickedItUp));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(repository.collected, 1);
      expect(find.text(_l10n.statusCompleted), findsWidgets);
      expect(find.text(_l10n.pickedItUp), findsNothing);
    });

    testWidgets('a delivery says it will reach them, with nothing to tap', (
      tester,
    ) async {
      await _pumpStatus(
        tester,
        _order(41, 'Ready', readyAtUtc: ready, fulfilment: 'Delivery'),
      );
      expect(find.text(_l10n.readyBodyDelivery), findsOneWidget);
      // At the foot of a list built lazily: scrolled there, so "nothing"
      // means not drawn, rather than not built yet.
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -3000),
      );
      await tester.pump();
      expect(find.text(_l10n.pickedItUp), findsNothing);
    });

    testWidgets('an order from before the choice stays neutral', (
      tester,
    ) async {
      await _pumpStatus(tester, _order(41, 'Ready', readyAtUtc: ready));
      expect(find.text(_l10n.readyBody), findsOneWidget);
      // At the foot of a list built lazily: scrolled there, so "nothing"
      // means not drawn, rather than not built yet.
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -3000),
      );
      await tester.pump();
      expect(find.text(_l10n.pickedItUp), findsNothing);
    });

    test('the local alert is worded the same way', () {
      final alerts = <String>[];
      final recorder = _BodyAlerts(alerts);
      for (final mode in ['Pickup', 'Delivery', null]) {
        announceOrderChange(
          recorder,
          _l10n,
          _order(41, 'Ready', readyAtUtc: ready, fulfilment: mode),
        );
      }
      expect(alerts, [
        _l10n.alertReadyBodyPickup(41),
        _l10n.alertReadyBodyDelivery(41),
        _l10n.alertReadyBody(41),
      ]);
    });
  });

  group('the tracking screen says what it knows, and only that', () {
    testWidgets('no time on a step that has not happened', (tester) async {
      final ready = DateTime.utc(2026, 8, 20, 7, 5);
      await _pumpStatus(tester, _order(41, 'Pending', readyAtUtc: ready));

      expect(find.text(Formatters.dateTime(ready, 'ar')), findsNothing);
    });

    testWidgets('each step tells a screen reader where the order is', (
      tester,
    ) async {
      await _pumpStatus(tester, _order(41, 'Pending'));

      expect(
        find.bySemanticsLabel(
          _l10n.timelineStep(_l10n.statusReady, _l10n.timelineNotYet),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the number the alerts cite, and "New order" when done', (
      tester,
    ) async {
      await _pumpStatus(tester, _order(41, 'Completed'));

      expect(find.text(_l10n.orderNumberTitle(41)), findsOneWidget);
      expect(find.text(_l10n.newOrder), findsOneWidget);
    });

    testWidgets('a cancelled order says it will not be made', (tester) async {
      await _pumpStatus(tester, _order(41, 'Cancelled'));

      expect(find.text(_l10n.cancelledBody), findsOneWidget);
    });

    testWidgets('identical cups once, with their extras and whose jar', (
      tester,
    ) async {
      const milk = CatalogueItemDto(
        itemId: 10,
        nameAr: 'حليب',
        nameEn: 'Milk',
        category: 'Extra',
        unit: 'ج',
        imageUrl: null,
        inStock: true,
        hasOwnStock: true,
        ownServingsLeft: 3,
        variants: [],
        allowedExtraItemIds: null,
      );
      const withMilk = OrderLineDto(
        drinkItemId: 1,
        drinkNameAr: 'قهوة',
        sugarSpoons: 1,
        variantId: null,
        sugarItemId: null,
        extraItemIds: [10],
        lineNote: null,
        drinkFromOwn: false,
        sugarFromOwn: false,
        ownExtraItemIds: [10],
      );
      await _pumpStatus(
        tester,
        _order(41, 'Pending', lines: const [withMilk, withMilk]),
        extras: const [milk],
      );

      expect(find.textContaining('×2'), findsOneWidget);
      expect(
        find.text(_l10n.extraFromMyMaterials(Formatters.isolate('حليب'))),
        findsOneWidget,
      );
    });
  });

  group('a guest order says whose it is', () {
    testWidgets('the row names the guest', (tester) async {
      await _pumpOrders(tester, [
        OrderSummaryDto(
          orderId: 42,
          status: 'Pending',
          createdAtUtc: DateTime.utc(2026, 8, 20, 7),
          readyAtUtc: null,
          handledAtUtc: null,
          locationText: '',
          onBehalfOfName: 'وفد الوزارة',
          notes: '',
          lines: [_line('قهوة')],
        ),
      ]);

      expect(find.textContaining('وفد الوزارة'), findsOneWidget);
    });
  });
}

/// Records each alert's body instead of showing it.
class _BodyAlerts extends OrderAlerts {
  _BodyAlerts(this.bodies) : super(FlutterLocalNotificationsPlugin());

  final List<String> bodies;

  @override
  Future<void> orderReady({
    required int orderId,
    required String title,
    required String body,
  }) async => bodies.add(body);
}
