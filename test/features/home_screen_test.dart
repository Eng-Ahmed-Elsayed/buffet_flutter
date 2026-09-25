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
import 'package:buffet_app/features/order/order_mode.dart';
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

const _tea = CatalogueItemDto(
  itemId: 1,
  nameAr: 'شاي',
  nameEn: 'Tea',
  category: 'Drink',
  unit: 'جرام',
  imageUrl: null,
  inStock: true,
  hasOwnStock: false,
  ownServingsLeft: 0,
  variants: [],
  allowedExtraItemIds: null,
);

/// Owned by the user, so it is listed under both jars.
const _coffee = CatalogueItemDto(
  itemId: 2,
  nameAr: 'قهوة تركي',
  nameEn: 'Turkish coffee',
  category: 'Drink',
  unit: 'جرام',
  imageUrl: null,
  inStock: true,
  hasOwnStock: true,
  ownServingsLeft: 3,
  variants: [],
  allowedExtraItemIds: null,
);

/// The buffet reads as empty — it must warn, and still order.
const _juice = CatalogueItemDto(
  itemId: 3,
  nameAr: 'عصير ليمون',
  nameEn: 'Lemon juice',
  category: 'Drink',
  unit: 'مل',
  imageUrl: null,
  inStock: false,
  hasOwnStock: false,
  ownServingsLeft: 0,
  variants: [],
  allowedExtraItemIds: null,
);

CatalogueResponse _catalogue(List<CatalogueItemDto> drinks) =>
    CatalogueResponse(
      drinks: drinks,
      sugars: const [],
      extras: const [],
      locations: const [],
      maxLines: 3,
      maxBuffetDrinks: 1,
    );

/// Seeds the composer was opened with, recorded by the routed harness.
final List<ComposerSeed> _opened = [];

Widget _app({
  bool canOrderForGuests = false,
  List<OrderSummaryDto> orders = const [],
  List<FavouriteDto> favourites = const [],
  List<CatalogueItemDto> drinks = const [_tea],
  Locale locale = const Locale('ar'),
  bool inShell = false,
  bool routed = false,
}) => ProviderScope(
  overrides: [
    catalogueProvider.overrideWith((ref) async => _catalogue(drinks)),
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
    home: inShell
        ? _inShell()
        : routed
        ? _routed()
        : const HomeScreen(),
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

/// Home under a router whose composer route records the seed it was opened
/// with, so a test can see exactly what a tap asked for.
Widget _routed() => Router.withConfig(
  config: GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(path: Routes.home, builder: (c, s) => const HomeScreen()),
      GoRoute(
        path: Routes.catalogue,
        builder: (c, s) {
          _opened.add(s.extra! as ComposerSeed);
          return const Scaffold(body: Text('composer'));
        },
      ),
    ],
  ),
);

Future<void> _pumpTall(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  setUp(_opened.clear);

  group('Home is for ordering, and for nothing a tab already holds', () {
    testWidgets('search and the menu are here; orders and materials are not', (
      tester,
    ) async {
      await _pumpTall(tester, _app());

      expect(find.text('ابحث عن مشروبك…'), findsOneWidget);
      expect(find.text('القائمة'), findsOneWidget);
      expect(find.text('شاي'), findsOneWidget);
      // My orders is the Orders tab and My materials a row on the Account
      // tab. A tile for either here would be a second control for a
      // destination the tab bar already shows.
      expect(find.text('طلباتي'), findsNothing);
      expect(find.text('موادي'), findsNothing);
    });

    testWidgets('the bell is here once, and settings is not', (tester) async {
      // Notifications live in the top bar. Settings is the Account tab, so
      // an icon for it here would be the same destination twice on screen.
      await _pumpTall(tester, _app());

      expect(find.byType(NotificationBell), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      // Nor are notifications or settings tiles in the body.
      expect(find.text('الإشعارات'), findsNothing);
      expect(find.text('الإعدادات'), findsNothing);
      // Anchored on something that IS expected, so this cannot pass by
      // rendering nothing at all.
      expect(find.text('القائمة'), findsOneWidget);
    });

    testWidgets('the guest action is absent without the privilege', (
      tester,
    ) async {
      await _pumpTall(tester, _app());

      expect(find.text('القائمة'), findsOneWidget);
      // Absent, not disabled: a disabled control advertises a capability
      // the user cannot obtain from this screen, which is worse than silence.
      expect(find.text('اطلب لضيف'), findsNothing);
    });

    testWidgets('the guest action appears with the privilege', (tester) async {
      await _pumpTall(tester, _app(canOrderForGuests: true));

      expect(find.text('اطلب لضيف'), findsOneWidget);
    });

    testWidgets('it renders in English too', (tester) async {
      await _pumpTall(
        tester,
        _app(locale: const Locale('en'), canOrderForGuests: true),
      );

      expect(find.text('Search your drink…'), findsOneWidget);
      expect(find.text('Menu'), findsOneWidget);
      expect(find.text('Order for a guest'), findsOneWidget);
    });
  });

  group('the menu groups by jar, and warns without blocking', () {
    testWidgets('an owned drink is listed under both jars, «من موادي» first', (
      tester,
    ) async {
      await _pumpTall(tester, _app(drinks: const [_tea, _coffee]));

      // Guide §7.1: grouped by the jar the order will draw from.
      expect(find.text('قهوة تركي'), findsNWidgets(2));
      final mineY = tester.getTopLeft(find.text('من موادي').last).dy;
      final buffetY = tester.getTopLeft(find.text('من البوفيه').last).dy;
      expect(mineY, lessThan(buffetY));
    });

    testWidgets('with one jar there is nothing to jump between', (
      tester,
    ) async {
      await _pumpTall(tester, _app());
      expect(find.text('شاي'), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('with two jars, a chip jumps to each', (tester) async {
      await _pumpTall(tester, _app(drinks: const [_tea, _coffee]));
      expect(find.byType(ActionChip), findsNWidgets(2));
    });

    testWidgets('on a small phone, the chip scrolls its section into view', (
      tester,
    ) async {
      // A lazy list does not build a heading that is off screen, so a chip
      // pointing at it would silently do nothing — a dead control. Home builds
      // the whole menu so the jump always lands.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          drinks: const [_coffee, _tea, _juice],
          favourites: [
            for (var i = 1; i <= 4; i++) _favourite(name: 'مفضل $i'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final heading = find.text('من البوفيه').last;
      expect(tester.getTopLeft(heading).dy, greaterThan(568));

      await tester.tap(find.widgetWithText(ActionChip, 'من البوفيه'));
      await tester.pumpAndSettle();

      final y = tester.getTopLeft(heading).dy;
      expect(y, greaterThanOrEqualTo(0));
      expect(y, lessThan(568));
    });

    testWidgets('a drink the buffet has run out of is marked and still taps', (
      tester,
    ) async {
      // Shortages warn but never block: recorded and physical stock drift.
      await _pumpTall(tester, _app(drinks: const [_juice], routed: true));

      expect(find.text('نفد من البوفيه'), findsOneWidget);
      await tester.tap(find.text('عصير ليمون'));
      await tester.pumpAndSettle();

      expect(_opened.single.drinkItemId, _juice.itemId);
    });

    testWidgets(
      'a tap opens the composer with the drink, from its row\'s jar',
      (tester) async {
        await _pumpTall(
          tester,
          _app(drinks: const [_tea, _coffee], routed: true),
        );

        // The first «قهوة تركي» is the one under «من موادي».
        await tester.tap(find.text('قهوة تركي').first);
        await tester.pumpAndSettle();

        expect(_opened.single.drinkItemId, _coffee.itemId);
        expect(_opened.single.drinkFromOwn, isTrue);
        expect(_opened.single.favourite, isNull);
      },
    );
  });

  group('search', () {
    testWidgets('finds a drink however its Arabic is spelled', (tester) async {
      await _pumpTall(tester, _app(drinks: const [_tea, _coffee]));

      await tester.enterText(find.byType(TextField), 'قهوه');
      await tester.pumpAndSettle();

      expect(find.text('قهوة تركي'), findsWidgets);
      expect(find.text('شاي'), findsNothing);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await _pumpTall(tester, _app());

      await tester.enterText(find.byType(TextField), 'كابتشينو');
      await tester.pumpAndSettle();

      expect(find.text('لا يوجد مشروب بهذا الاسم'), findsOneWidget);
    });

    testWidgets('favourites step aside while searching', (tester) async {
      await _pumpTall(tester, _app(favourites: [_favourite()]));
      expect(find.text('طلباتي المفضلة'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'شاي');
      await tester.pumpAndSettle();

      expect(find.text('طلباتي المفضلة'), findsNothing);
    });
  });

  group('what is owed to the user outranks what they might order', () {
    testWidgets('a ready drink is announced above the favourites and menu', (
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
      final menuY = tester.getTopLeft(find.text('القائمة')).dy;

      // Closing the app while waiting is normal, and this is the screen they
      // come back to.
      expect(outstandingY, lessThan(stripY));
      expect(stripY, lessThan(menuY));
    });

    testWidgets('on a small phone, the owed order and search stay in reach', (
      tester,
    ) async {
      // A full favourites strip once pushed the primary action of the whole
      // app out of the built viewport on a 320dp phone. Search is now the
      // first way into ordering, and it sits above the strip; this pins it
      // there, above the tab bar, with a live order and a full strip.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
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

      final barTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(
        tester.getBottomLeft(find.byType(TextField)).dy,
        lessThan(barTop),
        reason: 'Search must be reachable without scrolling, above the bar',
      );
      expect(
        tester.getBottomLeft(find.text('مشروبك جاهز')).dy,
        lessThan(barTop),
        reason: 'The owed order must be visible without scrolling',
      );
    });

    testWidgets('with no favourites, the first drink is in reach', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(inShell: true));
      await tester.pumpAndSettle();

      final barTop = tester.getTopLeft(find.byType(NavigationBar)).dy;
      expect(tester.getBottomLeft(find.text('شاي')).dy, lessThan(barTop));
    });

    testWidgets('no saved favourites means no strip at all', (tester) async {
      // Absent rather than an empty heading: a heading over no cards is noise
      // on the screen people open to order a drink.
      await _pumpTall(tester, _app());

      expect(find.text('طلباتي المفضلة'), findsNothing);
    });

    testWidgets('search renders before the catalogue arrives', (tester) async {
      await tester.pumpWidget(_app());
      // One frame only — the catalogue future has not resolved yet.
      await tester.pump();

      // A slow network must not stand between the user and the screen.
      expect(find.text('ابحث عن مشروبك…'), findsOneWidget);

      // Let the in-flight catalogue request finish, so the deliberate
      // single-frame pump above does not leave a timer pending.
      await tester.pumpAndSettle();
    });
  });
}
