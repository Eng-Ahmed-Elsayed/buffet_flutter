import 'dart:async';

import 'package:buffet_app/app/routes.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/app_harness.dart';

final _ar = lookupAppLocalizations(const Locale('ar'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    await loadAppFonts();
  });

  test("today's time alone; an earlier day with its date", () {
    final now = DateTime(2026, 9, 26, 15);
    final thisMorning = DateTime(2026, 9, 26, 9).toUtc();
    final yesterday = DateTime(2026, 9, 25, 9).toUtc();

    expect(
      Formatters.moment(thisMorning, 'en', now: now),
      Formatters.timeOfDay(thisMorning, 'en'),
    );
    expect(
      Formatters.moment(yesterday, 'en', now: now),
      Formatters.dateTime(yesterday, 'en'),
    );
  });

  testWidgets('an Orders tab with nothing ordered leads to ordering', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myOrdersProvider.overrideWith((r) async => const []),
          favouritesProvider.overrideWith(
            (r) async => const FavouritesResponse(favourites: []),
          ),
          catalogueProvider.overrideWith(
            (r) => Completer<CatalogueResponse>().future,
          ),
        ],
        child: const _Routed(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_ar.noOrdersTitle), findsOneWidget);
    await tester.tap(find.text(_ar.orderADrink));
    await tester.pumpAndSettle();
    expect(find.text('home-screen'), findsOneWidget);
  });
}

/// The Orders screen under a router with a Home to go to.
class _Routed extends StatefulWidget {
  const _Routed();

  @override
  State<_Routed> createState() => _RoutedState();
}

class _RoutedState extends State<_Routed> {
  late final GoRouter _router = GoRouter(
    initialLocation: Routes.myOrders,
    routes: [
      GoRoute(path: Routes.myOrders, builder: (c, s) => const MyOrdersScreen()),
      GoRoute(path: Routes.home, builder: (c, s) => const Text('home-screen')),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      testApp(home: Router.withConfig(config: _router));
}
