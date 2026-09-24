import 'package:buffet_app/app/employee_shell.dart';
import 'package:buffet_app/app/routes.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/home/home_screen.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/widgets/notification_bell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

OrderSummaryDto _order(int id, String status) => OrderSummaryDto(
  orderId: id,
  status: status,
  createdAtUtc: DateTime.utc(2026, 8, 20, 7),
  readyAtUtc: null,
  handledAtUtc: null,
  locationText: 'الدور الثالث',
  onBehalfOfName: null,
  notes: '',
  lines: const [],
);

FavouriteDto _favourite({String name = 'شاي'}) => FavouriteDto(
  favouriteId: 1,
  name: name,
  createdAtUtc: DateTime.utc(2026, 8, 24),
  lastUsedAtUtc: null,
  lines: const [],
);

CatalogueResponse _catalogue() => const CatalogueResponse(
  drinks: [
    CatalogueItemDto(
      itemId: 1,
      nameAr: 'شاي',
      nameEn: 'Tea',
      category: 'Tea',
      unit: 'جرام',
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
  maxLines: 3,
  maxBuffetDrinks: 1,
);

Widget _app({
  bool canOrderForGuests = false,
  List<OrderSummaryDto> orders = const [],
  List<FavouriteDto> favourites = const [],
  Locale locale = const Locale('ar'),
  bool inShell = false,
}) => ProviderScope(
  overrides: [
    catalogueProvider.overrideWith((ref) async => _catalogue()),
    favouritesProvider.overrideWith(
      (ref) async => FavouritesResponse(favourites: favourites),
    ),
    canOrderForGuestsProvider.overrideWith((ref) => canOrderForGuests),
    myOrdersProvider.overrideWith((ref) async => orders),
  ],
  child: MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: inShell ? _inShell() : const HomeScreen(),
  ),
);

/// Home as a user actually sees it: the first tab of the real employee shell,
/// with the tab bar taking its 80dp at the bottom.
Widget _inShell() {
  Widget stub(BuildContext c, GoRouterState s) => const SizedBox.shrink();
  return Router.withConfig(
    config: GoRouter(
      initialLocation: Routes.home,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => EmployeeShell(shell: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.home,
                  builder: (c, s) => const HomeScreen(),
                ),
              ],
            ),
            for (final tab in Routes.shellTabs.skip(1))
              StatefulShellBranch(
                routes: [GoRoute(path: tab, builder: stub)],
              ),
          ],
        ),
      ],
    ),
  );
}

Future<void> _pumpTall(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  group('the hub names every action the user may take', () {
    testWidgets('Home carries ordering; orders and materials live elsewhere', (
      tester,
    ) async {
      await _pumpTall(tester, _app());

      expect(find.text('طلب جديد'), findsOneWidget);
      // My orders is the Orders tab and My materials a row on the Account
      // tab. A tile for either here would be a second control for a
      // destination the tab bar already shows.
      expect(find.text('طلباتي'), findsNothing);
      expect(find.text('موادي'), findsNothing);
    });

    testWidgets('the bell is here once, and settings is not', (tester) async {
      // Notifications live in the top bar. Settings is the Account tab now,
      // so the old settings icon would be the same destination twice on
      // screen: once in the bar above, once in the tab bar below.
      await _pumpTall(tester, _app());

      expect(find.byType(NotificationBell), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.text('الإشعارات'), findsNothing);
      expect(find.text('الإعدادات'), findsNothing);

      // Anchored on an action that IS expected, so this cannot pass by
      // rendering nothing at all.
      expect(find.text('طلب جديد'), findsOneWidget);
    });

    testWidgets('the guest action is absent without the privilege', (
      tester,
    ) async {
      await _pumpTall(tester, _app());

      // Anchored on a tile that IS expected, so this cannot pass by rendering
      // nothing at all — a findsNothing on a blank screen always succeeds.
      expect(find.text('طلب جديد'), findsOneWidget);

      // Absent, not disabled: a disabled tile advertises a capability the user
      // cannot obtain from this screen, which is worse than silence.
      expect(find.text('طلب لضيف'), findsNothing);
    });

    testWidgets('the guest action appears with the privilege', (tester) async {
      await _pumpTall(tester, _app(canOrderForGuests: true));

      expect(find.text('طلب لضيف'), findsOneWidget);
    });

    testWidgets('it renders in English too', (tester) async {
      await _pumpTall(
        tester,
        _app(canOrderForGuests: true, locale: const Locale('en')),
      );

      expect(find.text('New order'), findsOneWidget);
      expect(find.text('Guest order'), findsOneWidget);
    });
  });

  group('what is owed to the user outranks what they might order', () {
    testWidgets('a ready drink is announced above the actions', (tester) async {
      await _pumpTall(tester, _app(orders: [_order(7, 'Ready')]));

      final cardY = tester.getTopLeft(find.text('مشروبك جاهز')).dy;
      final newOrderY = tester.getTopLeft(find.text('طلب جديد')).dy;

      // Closing the app while waiting is normal, and this is the screen they
      // come back to.
      expect(cardY, lessThan(newOrderY));
    });

    testWidgets('favourites sit above the actions but below what is owed', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          orders: [_order(7, 'Ready')],
          favourites: [_favourite(name: 'قهوة الصبح')],
        ),
      );

      final outstandingY = tester.getTopLeft(find.text('مشروبك جاهز')).dy;
      final stripY = tester.getTopLeft(find.text('طلباتي المفضلة')).dy;
      final newOrderY = tester.getTopLeft(find.text('طلب جديد')).dy;

      expect(outstandingY, lessThan(stripY));
      expect(stripY, lessThan(newOrderY));
    });

    testWidgets('the primary action survives a full strip on a small phone', (
      tester,
    ) async {
      // The strip sits above "New order", and a version of it that put one
      // card per row on a 320dp phone pushed the primary action of the whole
      // app off the first screen — not merely below the fold, but out of the
      // lazily-built viewport entirely. The responsive suite did not catch it:
      // it checks for OVERFLOW, and nothing overflowed.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          // Inside the real shell: the tab bar takes the bottom 80dp, so the
          // action must clear the bar, not merely the screen's edge.
          inShell: true,
          orders: [_order(7, 'Ready')],
          favourites: [
            for (var i = 1; i <= 6; i++)
              FavouriteDto(
                favouriteId: i,
                name: 'قهوة تركي سادة (بدون سكر) + حليب $i',
                createdAtUtc: DateTime.utc(2026, 8, 24),
                lastUsedAtUtc: null,
                lines: const [],
              ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('طلب جديد'), findsOneWidget);
      final bottom = tester.getBottomLeft(find.text('طلب جديد')).dy;
      final barTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(
        bottom,
        lessThan(barTop),
        reason: 'New order must be reachable without scrolling, above the bar',
      );
    });

    testWidgets('no saved favourites means no strip at all', (tester) async {
      // Absent rather than an empty heading: a heading over no cards is noise
      // on the screen people open to order a drink.
      await _pumpTall(tester, _app());

      expect(find.text('طلباتي المفضلة'), findsNothing);
    });

    testWidgets('the actions render before the catalogue arrives', (
      tester,
    ) async {
      await tester.pumpWidget(_app());
      // One frame only — the catalogue future has not resolved yet.
      await tester.pump();

      // A slow network must not stand between the user and the one thing they
      // opened the app to do.
      expect(find.text('طلب جديد'), findsOneWidget);

      // Let the in-flight catalogue request finish, so the deliberate
      // single-frame pump above does not leave a timer pending.
      await tester.pumpAndSettle();
    });
  });
}
