import 'package:buffet_app/data/api/api_exception.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/repositories/catalogue_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/order/composer_controller.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/favourites_screen.dart';
import 'package:buffet_app/features/order/order_mode.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _l10n = lookupAppLocalizations(const Locale('ar'));

CatalogueItemDto _item(int id, String nameAr) => CatalogueItemDto(
  itemId: id,
  nameAr: nameAr,
  nameEn: '',
  category: 'Drink',
  unit: 'جرام',
  imageUrl: null,
  inStock: true,
  hasOwnStock: false,
  ownServingsLeft: 0,
  variants: const [],
  allowedExtraItemIds: null,
);

OrderLineDto _line(int drinkId, String name, {int spoons = 1}) => OrderLineDto(
  drinkItemId: drinkId,
  drinkNameAr: name,
  sugarSpoons: spoons,
  variantId: null,
  sugarItemId: null,
  extraItemIds: const [],
  lineNote: null,
  drinkFromOwn: false,
  sugarFromOwn: false,
  ownExtraItemIds: const [],
);

FavouriteDto _favourite(List<OrderLineDto> lines, {int id = 5}) => FavouriteDto(
  favouriteId: id,
  name: 'قهوتي',
  createdAtUtc: DateTime.utc(2026, 8, 24),
  lastUsedAtUtc: null,
  lines: lines,
);

/// A roomy buffet cap: these tests are about replaying and leaving, not the
/// cap, which has its own group below.
final _menu = CatalogueResponse(
  drinks: [_item(1, 'قهوة'), _item(2, 'شاي')],
  sugars: const [],
  extras: const [],
  locations: const [],
  maxBuffetDrinks: 5,
);

/// Fails every placement, as a dropped connection would.
class _FailingRepository extends CatalogueRepository {
  _FailingRepository({this.statusCode}) : super(Dio());

  /// Null for a dropped connection; a 4xx for a definite refusal.
  final int? statusCode;

  int attempts = 0;
  final keys = <String?>[];
  final requests = <PlaceOrderApiRequest>[];

  @override
  Future<PlaceOrderResponse> placeOrder({
    required PlaceOrderApiRequest request,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    attempts++;
    keys.add(request.idempotencyKey);
    requests.add(request);
    throw ApiException(
      message: statusCode == null ? 'تعذّر الاتصال' : 'تجاوزت حد البوفيه',
      statusCode: statusCode,
      isNetworkFailure: statusCode == null,
    );
  }
}

/// A home screen that opens the composer, the favourites list, and the
/// composer itself — the real routes, built in initState (CLAUDE.md).
class _Routed extends StatefulWidget {
  const _Routed({required this.seed});

  final ComposerSeed seed;

  @override
  State<_Routed> createState() => _RoutedState();
}

class _RoutedState extends State<_Routed> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/order', extra: widget.seed),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: '/order',
          builder: (context, state) =>
              ComposerScreen(seed: state.extra! as ComposerSeed),
        ),
        GoRoute(
          path: '/favourites-list',
          builder: (context, state) =>
              const FavouritesScreen(returnsPick: true),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routerConfig: _router,
  );
}

Future<_FailingRepository> _open(
  WidgetTester tester, {
  ComposerSeed seed = const ComposerSeed(),
  List<FavouriteDto> favourites = const [],
  bool canOrderForGuests = false,
  int? failWith,
  Size size = const Size(1400, 4000),
  bool fulfilmentChosen = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = _FailingRepository(statusCode: failWith);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogueProvider.overrideWith((ref) async => _menu),
        favouritesProvider.overrideWith(
          (ref) async => FavouritesResponse(favourites: favourites),
        ),
        canOrderForGuestsProvider.overrideWith((ref) => canOrderForGuests),
        catalogueRepositoryProvider.overrideWithValue(repository),
      ],
      child: _Routed(seed: seed),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // A returning user: the pickup-or-delivery choice is remembered (§7.8),
  // so these journeys are about what they test, not about choosing.
  if (fulfilmentChosen) {
    ProviderScope.containerOf(tester.element(find.byType(ComposerScreen)))
        .read(composerControllerProvider.notifier)
        .setFulfilment(Fulfilment.pickup);
    await tester.pump();
  }
  return repository;
}

ComposerState _state(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ComposerScreen)))
        .read(composerControllerProvider);

void main() {
  group('a favourite is replayed whole', () {
    test('coffee and tea come back as coffee and tea', () {
      final c = ComposerController()
        ..applyLimits(maxLines: 5, maxBuffetDrinks: 5)
        ..applyFavourite(
          _favourite([_line(1, 'قهوة'), _line(2, 'شاي')]),
          _menu.drinks,
        );

      expect(c.state.allLines.map((l) => l.drink.itemId), [1, 2]);
      expect(c.state.toRequest().lines, hasLength(2));
    });

    test('three coffees come back as three', () {
      final c = ComposerController()
        ..applyLimits(maxLines: 5, maxBuffetDrinks: 5)
        ..applyFavourite(
          _favourite([_line(1, 'قهوة'), _line(1, 'قهوة'), _line(1, 'قهوة')]),
          _menu.drinks,
        );

      expect(c.state.allLines, hasLength(3));
    });

    test('a retired drink is reported, and the rest still come back', () {
      final c = ComposerController();
      final result = c.applyFavourite(
        _favourite([_line(1, 'قهوة'), _line(99, 'كابتشينو')]),
        _menu.drinks,
      );

      expect(c.state.allLines.map((l) => l.drink.itemId), [1]);
      expect(result.retired.single.drinkNameAr, 'كابتشينو');
    });

    test('drinks past the line cap are reported, not squeezed in', () {
      final c = ComposerController()
        ..applyLimits(maxLines: 2, maxBuffetDrinks: 5);
      final result = c.applyFavourite(
        _favourite([_line(1, 'قهوة'), _line(2, 'شاي'), _line(1, 'قهوة')]),
        _menu.drinks,
      );

      expect(c.state.allLines, hasLength(2));
      expect(result.overCap, hasLength(1));
    });

    testWidgets('a retired drink is named on Review', (tester) async {
      await _open(
        tester,
        seed: ComposerSeed(
          favourite: _favourite([_line(1, 'قهوة'), _line(99, 'كابتشينو')]),
        ),
      );

      expect(find.text(_l10n.reviewOrderTitle), findsOneWidget);
      expect(find.text(_l10n.favouriteNotAllAddedTitle), findsOneWidget);
      expect(find.textContaining('كابتشينو'), findsOneWidget);
    });
  });

  group('"show all" from the composer returns the pick to it', () {
    testWidgets('no second composer is stacked on the first', (tester) async {
      // Five favourites, so the strip truncates and offers "show all".
      await _open(
        tester,
        favourites: [
          for (var i = 1; i <= 5; i++)
            _favourite([_line(i.isOdd ? 1 : 2, 'قهوة')], id: i),
        ],
      );

      await tester.tap(find.text(_l10n.favouritesShowAll(5)));
      await tester.pumpAndSettle();
      expect(find.byType(FavouritesScreen), findsOneWidget);

      await tester.tap(find.textContaining('قهوتي').last);
      await tester.pumpAndSettle();

      // Back in the SAME composer, on Review, with the favourite in it.
      expect(find.byType(FavouritesScreen), findsNothing);
      expect(find.byType(ComposerScreen), findsOneWidget);
      expect(find.text(_l10n.reviewOrderTitle), findsOneWidget);
      expect(_state(tester).allLines, hasLength(1));
    });
  });

  group('leaving never throws an order away without asking', () {
    testWidgets('back from Review asks; "keep ordering" stays', (tester) async {
      await _open(
        tester,
        seed: ComposerSeed(
          favourite: _favourite([_line(1, 'قهوة'), _line(2, 'شاي')]),
        ),
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_l10n.discardOrderTitle), findsOneWidget);

      await tester.tap(find.text(_l10n.keepOrdering));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerScreen), findsOneWidget);
      expect(_state(tester).allLines, hasLength(2));
    });

    testWidgets('"discard" leaves', (tester) async {
      await _open(
        tester,
        seed: ComposerSeed(favourite: _favourite([_line(1, 'قهوة')])),
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.discardOrder));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerScreen), findsNothing);
    });

    testWidgets('a single drink opened from Home backs out without asking', (
      tester,
    ) async {
      await _open(tester, seed: const ComposerSeed(drinkItemId: 1));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(_l10n.discardOrderTitle), findsNothing);
      expect(find.byType(ComposerScreen), findsNothing);
    });
  });

  group('a failed placement stays said, and the retry is the same order', () {
    testWidgets('the failure stays on Review, and a retry reuses the key', (
      tester,
    ) async {
      final repository = await _open(
        tester,
        seed: ComposerSeed(favourite: _favourite([_line(1, 'قهوة')])),
      );

      await tester.tap(find.text(_l10n.placeOrder));
      await tester.pumpAndSettle();
      // Long past any SnackBar's four seconds.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text(_l10n.placeFailedTitle), findsOneWidget);

      await tester.tap(find.text(_l10n.placeOrder));
      await tester.pumpAndSettle();
      expect(repository.attempts, 2);
      expect(repository.keys.toSet(), hasLength(1));
    });

    testWidgets('leaving after a failure warns it may have gone through', (
      tester,
    ) async {
      await _open(
        tester,
        seed: ComposerSeed(favourite: _favourite([_line(1, 'قهوة')])),
      );
      await tester.tap(find.text(_l10n.placeOrder));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_l10n.discardAfterFailureBody), findsOneWidget);
    });
  });

  group('pickup or delivery is asked, and never by a disabled button', () {
    testWidgets('neither chosen: Place order says so, and sends nothing', (
      tester,
    ) async {
      final repository = await _open(
        tester,
        seed: ComposerSeed(favourite: _favourite([_line(1, 'قهوة')])),
        fulfilmentChosen: false,
      );
      expect(find.text(_l10n.fulfilmentTitle), findsOneWidget);

      await tester.tap(find.text(_l10n.placeOrder));
      await tester.pumpAndSettle();
      expect(repository.attempts, 0);
      expect(find.text(_l10n.fulfilmentRequired), findsOneWidget);

      await tester.tap(find.text(_l10n.fulfilmentPickup));
      await tester.pumpAndSettle();
      expect(find.text(_l10n.fulfilmentRequired), findsNothing);
      await tester.tap(find.text(_l10n.placeOrder));
      await tester.pumpAndSettle();
      expect(repository.requests.single.fulfilment, 'Pickup');
    });

    testWidgets('delivery with nowhere to deliver to asks on the location '
        'field', (tester) async {
      final repository = await _open(
        tester,
        seed: ComposerSeed(favourite: _favourite([_line(1, 'قهوة')])),
        fulfilmentChosen: false,
      );
      await tester.tap(find.text(_l10n.fulfilmentDelivery));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.placeOrder));
      await tester.pumpAndSettle();

      // The server would refuse it with a 400; the field says why first.
      expect(repository.attempts, 0);
      expect(find.text(_l10n.deliveryNeedsLocation), findsOneWidget);
      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, _l10n.locationHint),
      );
      expect(field.focusNode?.hasFocus, isTrue);

      await tester.enterText(
        find.widgetWithText(TextField, _l10n.locationHint),
        'Desk 3',
      );
      await tester.tap(find.text(_l10n.placeOrder));
      await tester.pumpAndSettle();
      final sent = repository.requests.single;
      expect(sent.fulfilment, 'Delivery');
      expect(sent.locationText, 'Desk 3');
    });
  });

  group('the choice is order-wide and remembered', () {
    testWidgets('Review opens on the last choice made on this device', (
      tester,
    ) async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'read' &&
                (call.arguments as Map)['key'] == 'pref_fulfilment'
            ? 'Delivery'
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _open(
        tester,
        seed: ComposerSeed(favourite: _favourite([_line(1, 'قهوة')])),
        fulfilmentChosen: false,
      );
      expect(_state(tester).fulfilment, Fulfilment.delivery);
    });

    test('it survives adding a drink and a confirmed order', () {
      final c = ComposerController()
        ..applyLimits(maxLines: 5, maxBuffetDrinks: 5)
        ..restoreFulfilment(Fulfilment.delivery)
        ..selectDrink(_menu.drinks.first);
      expect(c.state.fulfilment, Fulfilment.delivery);

      c.addLine();
      expect(c.state.fulfilment, Fulfilment.delivery);
      c.resetAfterConfirmedOrder();
      expect(c.state.fulfilment, Fulfilment.delivery);

      // A remembered choice never overrides one made on this order.
      c
        ..setFulfilment(Fulfilment.pickup)
        ..restoreFulfilment(Fulfilment.delivery);
      expect(c.state.fulfilment, Fulfilment.pickup);
    });
  });

  group('a guest order without the name goes to the name', () {
    testWidgets('tapping a drink focuses the name field', (tester) async {
      await _open(
        tester,
        seed: const ComposerSeed(mode: OrderMode.guest),
        canOrderForGuests: true,
      );

      await tester.tap(find.text('شاي'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, _l10n.guestOrderLabel),
      );
      expect(field.focusNode?.hasFocus, isTrue);
      expect(find.text(_l10n.guestNameRequired), findsOneWidget);
    });
  });

  group('a replayed favourite keeps to the buffet cap', () {
    test('buffet drinks past the cap are reported, not added', () {
      // A saved guest order of three coffees, replayed as the user's own.
      final c = ComposerController()
        ..applyLimits(maxLines: 5, maxBuffetDrinks: 1);
      final result = c.applyFavourite(
        _favourite([_line(1, 'قهوة'), _line(1, 'قهوة'), _line(1, 'قهوة')]),
        _menu.drinks,
      );

      expect(c.state.allLines, hasLength(1));
      expect(result.overBuffetCap, hasLength(2));
      expect(c.state.exceedsBuffetCap, isFalse);
    });
  });

  group('a definite refusal is not presented as maybe-sent', () {
    testWidgets('a 400 says "not accepted", and leaving says nothing of '
        'My orders', (tester) async {
      await _open(
        tester,
        seed: ComposerSeed(favourite: _favourite([_line(1, 'قهوة')])),
        failWith: 400,
      );
      await tester.tap(find.text(_l10n.placeOrder));
      await tester.pumpAndSettle();

      expect(find.text(_l10n.placeRejectedTitle), findsOneWidget);
      expect(find.text(_l10n.placeFailedTitle), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_l10n.discardOrderBody), findsOneWidget);
      expect(find.text(_l10n.discardAfterFailureBody), findsNothing);
    });
  });

  group('the notices never squeeze Review on a small phone', () {
    testWidgets('both notices, 320dp, 2x text, keyboard up', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(
        tester,
        size: const Size(320, 640),
        seed: ComposerSeed(
          favourite: _favourite([_line(1, 'قهوة'), _line(99, 'كابتشينو')]),
        ),
      );
      await tester.ensureVisible(find.text(_l10n.placeOrder));
      await tester.tap(find.text(_l10n.placeOrder));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('a failed placement is seen, wherever Review was scrolled to', () {
    testWidgets('the notice is brought into view', (tester) async {
      await _open(
        tester,
        size: const Size(360, 640),
        seed: ComposerSeed(
          favourite: _favourite([_line(1, 'قهوة'), _line(2, 'شاي')]),
        ),
      );
      // Scrolled to the bottom of Review, where the order was finished.
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -2000),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_l10n.placeOrder));
      await tester.pumpAndSettle();

      final notice = tester.getRect(find.text(_l10n.placeFailedTitle));
      final viewport = tester.getRect(find.byType(SingleChildScrollView).last);
      expect(viewport.contains(notice.topLeft), isTrue);
      expect(viewport.contains(notice.bottomRight), isTrue);
    });
  });
}
