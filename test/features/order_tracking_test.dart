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

  final OrderSummaryDto order;

  @override
  Future<OrderSummaryDto> fetchOrder({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async => order;

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

Future<void> _pumpStatus(WidgetTester tester, OrderSummaryDto order) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        orderRepositoryProvider.overrideWithValue(_OneOrderRepo(order)),
        catalogueProvider.overrideWith(
          (r) async => const CatalogueResponse(
            drinks: [],
            sugars: [],
            extras: [],
            locations: [],
          ),
        ),
      ],
      child: testApp(home: const _RoutedStatus()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
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
      expect(find.text(Formatters.timeOfDay(ready, 'ar')), findsOneWidget);
      expect(find.text(Formatters.timeOfDay(handled, 'ar')), findsOneWidget);
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
}
