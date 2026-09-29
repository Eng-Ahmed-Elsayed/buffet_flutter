import 'package:buffet_app/data/models/auth_models.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/repositories/catalogue_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/order/composer_controller.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/order_mode.dart';
import 'package:buffet_app/features/order/self_order_outcome.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/widgets/quantity_stepper.dart';
import 'package:buffet_app/shared/widgets/section_header.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_auth_controller.dart';

CatalogueItemDto _item(
  int id,
  String nameAr,
  String category, {
  bool hasOwnStock = false,
  int ownServingsLeft = 0,
  List<int>? allowedExtraItemIds,
  List<VariantDto> variants = const [],
}) => CatalogueItemDto(
  itemId: id,
  nameAr: nameAr,
  nameEn: '',
  category: category,
  unit: 'جرام',
  imageUrl: null,
  inStock: true,
  hasOwnStock: hasOwnStock,
  ownServingsLeft: ownServingsLeft,
  variants: variants,
  allowedExtraItemIds: allowedExtraItemIds,
);

LoginResponse _session({bool canOrderForGuests = false}) => LoginResponse(
  token: 't',
  expiresUtc: DateTime.utc(2030),
  username: 'sara@company.com',
  displayName: 'سارة',
  role: 'Employee',
  department: 'المالية',
  mustChangePassword: false,
  canOrderForGuests: canOrderForGuests,
);

FavouriteDto _favourite({int id = 1, String name = 'قهوتي'}) => FavouriteDto(
  favouriteId: id,
  name: name,
  createdAtUtc: DateTime.utc(2026, 8, 24),
  lastUsedAtUtc: null,
  lines: const [],
);

Widget _app(
  CatalogueResponse catalogue, {
  bool canOrderForGuests = false,
  OrderMode mode = OrderMode.self,
  List<FavouriteDto> favourites = const [],
  int maxFavourites = 20,
  ComposerSeed? seed,
}) => ProviderScope(
  overrides: [
    catalogueProvider.overrideWith((ref) async => catalogue),
    favouritesProvider.overrideWith(
      (ref) async => FavouritesResponse(
        favourites: favourites,
        maxFavourites: maxFavourites,
      ),
    ),
    canOrderForGuestsProvider.overrideWith(
      (ref) => _session(canOrderForGuests: canOrderForGuests).canOrderForGuests,
    ),
  ],
  child: MaterialApp(
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: ComposerScreen(seed: seed ?? ComposerSeed(mode: mode)),
  ),
);

/// Lays the composer out on a tall surface.
///
/// A `ListView` only builds what fits, and these assertions are about grouping
/// and filtering rather than scrolling — a phone-sized viewport would fail them
/// for the wrong reason.
Future<void> _pumpTall(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// The Arabic double-portion hint, as it appears in `app_ar.arb`.
const _doublesHint =
    'اخترت إضافة تحتوي عليها طريقة التحضير أصلًا، لذا ستُستخدم حصة مضاعفة.';

void main() {
  group('§3 — the pickers group by which jar the order draws on', () {
    testWidgets(
      'owned drinks sit under "my materials", buffet under "the buffet"',
      (tester) async {
        await _pumpTall(
          tester,
          _app(
            CatalogueResponse(
              drinks: [
                _item(1, 'قهوة', 'Drink'),
                _item(
                  2,
                  'نعناع',
                  'Drink',
                  hasOwnStock: true,
                  ownServingsLeft: 4,
                ),
              ],
              sugars: const [],
              extras: const [],
              locations: const [],
            ),
          ),
        );

        // The section headings, not the jump chips that repeat their names.
        expect(find.widgetWithText(SectionHeader, 'من موادي'), findsOneWidget);
        expect(
          find.widgetWithText(SectionHeader, 'من البوفيه'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an owned item with NOTHING left still shows under "my materials"',
      (tester) async {
        // hasOwnStock says the user owns some; it says nothing about how much,
        // and the ledger permits negative balances by design. Hiding it would be
        // a control removed on a stock reading.
        await _pumpTall(
          tester,
          _app(
            CatalogueResponse(
              drinks: [
                _item(
                  2,
                  'نعناع',
                  'Drink',
                  hasOwnStock: true,
                  ownServingsLeft: 0,
                ),
              ],
              sugars: const [],
              extras: const [],
              locations: const [],
            ),
          ),
        );

        expect(find.widgetWithText(SectionHeader, 'من موادي'), findsOneWidget);
        // Shown, never hidden — and once per jar as everywhere else.
        expect(find.text('نعناع'), findsNWidgets(2));
      },
    );

    testWidgets('no headings at all when the user owns nothing', (
      tester,
    ) async {
      // Headings over a single section are noise for the majority.
      await _pumpTall(
        tester,
        _app(
          CatalogueResponse(
            drinks: [_item(1, 'قهوة', 'Drink')],
            sugars: const [],
            extras: const [],
            locations: const [],
          ),
        ),
      );

      expect(find.text('من موادي'), findsNothing);
      expect(find.text('من البوفيه'), findsNothing);
      expect(find.text('قهوة'), findsOneWidget);
    });
  });

  group('§6 — the extras row follows the selected drink', () {
    testWidgets('an unrestricted drink offers every extra on its step', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          CatalogueResponse(
            drinks: [_item(1, 'قهوة', 'Drink')],
            sugars: const [],
            extras: [_item(9, 'حليب', 'Extra'), _item(10, 'قرفة', 'Extra')],
            locations: const [],
          ),
        ),
      );

      // Extras belong to a drink, so they are offered on the drink's own
      // step rather than before one is chosen.
      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();

      expect(find.text('حليب'), findsOneWidget);
      expect(find.text('قرفة'), findsOneWidget);
    });

    testWidgets('a restricted drink hides the extras it does not permit', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          CatalogueResponse(
            drinks: [
              _item(1, 'قهوة', 'Drink', allowedExtraItemIds: const [9]),
            ],
            sugars: const [],
            extras: [_item(9, 'حليب', 'Extra'), _item(10, 'قرفة', 'Extra')],
            locations: const [],
          ),
        ),
      );

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();

      expect(find.text('حليب'), findsOneWidget);
      // Offering this would produce a drink that arrives wrong: the server
      // drops it while the order still succeeds.
      expect(find.text('قرفة'), findsNothing);
    });

    testWidgets('a drink permitting NO extras hides the whole row', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          CatalogueResponse(
            drinks: [_item(1, 'قهوة', 'Drink', allowedExtraItemIds: const [])],
            sugars: const [],
            extras: [_item(9, 'حليب', 'Extra')],
            locations: const [],
          ),
        ),
      );

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();

      // An empty list means none — never conflated with null, which is
      // unrestricted. The heading goes too, rather than sitting over nothing.
      expect(find.text('حليب'), findsNothing);
      expect(find.text('إضافات'), findsNothing);
    });
  });

  group('§8 — the double-portion warning', () {
    CatalogueResponse withRecipe() => CatalogueResponse(
      drinks: [
        _item(
          1,
          'قهوة',
          'Drink',
          variants: const [
            VariantDto(
              variantId: 71,
              nameAr: 'فرنساوي',
              nameEn: 'French',
              isDefault: true,
              ingredientItemIds: [9],
            ),
            VariantDto(
              variantId: 72,
              nameAr: 'غامق',
              nameEn: 'Dark',
              isDefault: false,
              ingredientItemIds: [],
            ),
          ],
        ),
      ],
      sugars: const [],
      extras: [_item(9, 'حليب', 'Extra')],
      locations: const [],
    );

    testWidgets('the hint appears only once the doubling extra is ticked', (
      tester,
    ) async {
      await _pumpTall(tester, _app(withRecipe()));

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();

      // Flagged on the chip, but nothing is doubled until it is chosen.
      expect(find.text(_doublesHint), findsNothing);

      await tester.tap(find.text('حليب'));
      await tester.pumpAndSettle();
      expect(find.text(_doublesHint), findsOneWidget);
    });

    testWidgets('the hint goes away when the preparation changes', (
      tester,
    ) async {
      await _pumpTall(tester, _app(withRecipe()));

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حليب'));
      await tester.pumpAndSettle();
      expect(find.text(_doublesHint), findsOneWidget);

      // غامق pours no milk, so the same ticked extra stops doubling.
      await tester.tap(find.text('غامق'));
      await tester.pumpAndSettle();
      expect(find.text(_doublesHint), findsNothing);
    });

    testWidgets('the extra stays selectable — annotate, never filter', (
      tester,
    ) async {
      await _pumpTall(tester, _app(withRecipe()));

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حليب'));
      await tester.pumpAndSettle();

      // The chip is still there and still on: an ingredient cannot be
      // declined, and a double portion is a legitimate thing to order.
      expect(find.text('حليب'), findsOneWidget);
      final chip = tester.widget<FilterChip>(find.byType(FilterChip));
      expect(chip.selected, isTrue);
      expect(chip.onSelected, isNotNull);

      // And the way on never goes off for it.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'متابعة'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('§2 — who the order is for is settled before it is composed', () {
    CatalogueResponse oneDrink() => CatalogueResponse(
      drinks: [_item(1, 'قهوة', 'Drink')],
      sugars: const [],
      extras: const [],
      locations: const [],
    );

    testWidgets('a self order never asks for a guest, privilege or not', (
      tester,
    ) async {
      await _pumpTall(tester, _app(oneDrink(), canOrderForGuests: true));

      // Anchored on the drink picker, so this cannot pass by rendering
      // nothing at all — a findsNothing on a blank screen always succeeds.
      expect(find.text('قهوة'), findsOneWidget);

      // The field used to appear in the footer for anyone holding the
      // privilege, which made an ordinary order and a guest order look
      // identical. Self mode has no guest field at all — not an empty one.
      expect(find.text('اسم الضيف'), findsNothing);
    });

    testWidgets('a guest order asks who it is for, first', (tester) async {
      await _pumpTall(
        tester,
        _app(oneDrink(), canOrderForGuests: true, mode: OrderMode.guest),
      );

      // The banner says it is a guest order; the field asks for the name.
      expect(find.text('طلب لضيف'), findsWidgets);
      expect(find.text('اسم الضيف'), findsOneWidget);

      // And it is above the drink picker rather than below the whole order.
      final guestY = tester.getTopLeft(find.text('اسم الضيف')).dy;
      final drinkY = tester.getTopLeft(find.text('قهوة')).dy;
      expect(guestY, lessThan(drinkY));
    });

    testWidgets('a guest seed degrades to a self order without the privilege', (
      tester,
    ) async {
      await _pumpTall(tester, _app(oneDrink(), mode: OrderMode.guest));

      expect(find.text('قهوة'), findsOneWidget);

      // The privilege is read from the token's claims server-side, so offering
      // the field to someone without it would produce a rejection they could
      // not act on. Falling back to a self order is the honest degradation.
      expect(find.text('اسم الضيف'), findsNothing);
    });

    testWidgets('a drink without a guest name shows why, and waits', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(oneDrink(), canOrderForGuests: true, mode: OrderMode.guest),
      );

      // The name is what lifts the buffet cap, so nothing moves on without
      // it. The drink is NOT dead: tapping it reveals what is missing, rather
      // than a control that does nothing and says nothing.
      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();

      expect(find.text('اكتب اسم الضيف لإتمام الطلب.'), findsOneWidget);
      expect(find.text('متابعة'), findsNothing, reason: 'still choosing');
    });
  });

  group('favourites are one tap from the ordering screen (§12)', () {
    CatalogueResponse plain() => CatalogueResponse(
      drinks: [_item(1, 'قهوة', 'Drink')],
      sugars: const [],
      extras: const [],
      locations: const [],
    );

    testWidgets('the strip is offered on the composer itself', (tester) async {
      await _pumpTall(
        tester,
        _app(plain(), favourites: [_favourite(name: 'قهوة الصبح')]),
      );

      // It lives on the hub too, but staff reach this screen by pushing it
      // from the queue and never see the hub — so a strip that existed only
      // there would take the one-tap repeat away from them entirely.
      expect(find.textContaining('قهوة الصبح'), findsOneWidget);
    });

    testWidgets('it stays while composing, and a tap adds to the order', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          // Room for two buffet drinks: this is about the strip, not the cap.
          CatalogueResponse(
            drinks: [_item(1, 'قهوة', 'Drink')],
            sugars: const [],
            extras: const [],
            locations: const [],
            maxBuffetDrinks: 2,
          ),
          favourites: [_favouriteOf(1)],
        ),
      );

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أضف مشروبًا آخر'));
      await tester.pumpAndSettle();

      // Back on the first step with a drink in the order, the strip is still
      // offered: backing out to pick a favourite used to find it gone.
      expect(find.textContaining('قهوتي'), findsOneWidget);

      // And a tap adds the favourite after the drink already in the order.
      await tester.tap(find.textContaining('قهوتي'));
      await tester.pumpAndSettle();
      final composer = ProviderScope.containerOf(
        tester.element(find.byType(ComposerScreen)),
      ).read(composerControllerProvider);
      expect(composer.allLines, hasLength(2));
    });

    testWidgets('saving is offered once there is an order to save', (
      tester,
    ) async {
      await _pumpTall(tester, _app(plain()));

      // Nothing composed yet — nothing to save.
      expect(find.text('احفظ كطلب مفضل'), findsNothing);

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();

      expect(find.text('احفظ كطلب مفضل'), findsOneWidget);
    });

    testWidgets('at the cap the switch is off AND the reason is on screen', (
      tester,
    ) async {
      // The cap is structural — the server refuses past it — which is the one
      // kind of limit this app disables a control on. It is still never a dead
      // end: the banner says what the limit is and how to make room.
      await _pumpTall(
        tester,
        _app(plain(), favourites: [_favourite()], maxFavourites: 1),
      );

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();

      expect(find.text('وصلت إلى الحد الأقصى'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isNull);
    });
  });

  group('the guest field shows what the order will actually carry', () {
    testWidgets('typing a two-word name keeps the space between them', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          CatalogueResponse(
            drinks: [_item(1, 'قهوة', 'Drink')],
            sugars: const [],
            extras: const [],
            locations: const [],
          ),
          canOrderForGuests: true,
          mode: OrderMode.guest,
        ),
      );

      // On the way to "أحمد محمد" the user passes through "أحمد ". The state
      // trims that back, and a sync comparing raw text would read the trim as
      // a divergence and snatch the space away as it was typed.
      await tester.enterText(find.byType(TextField).first, 'أحمد ');
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        'أحمد ',
      );
    });

    testWidgets('a confirmed order clears the visible name, not just state', (
      tester,
    ) async {
      late WidgetRef captured;

      await _pumpTall(
        tester,
        ProviderScope(
          overrides: [
            catalogueProvider.overrideWith(
              (ref) async => CatalogueResponse(
                drinks: [_item(1, 'قهوة', 'Drink')],
                sugars: const [],
                extras: const [],
                locations: const [],
              ),
            ),
            canOrderForGuestsProvider.overrideWith((ref) => true),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Consumer(
              builder: (context, ref, _) {
                captured = ref;
                return const ComposerScreen(
                  seed: ComposerSeed(mode: OrderMode.guest),
                );
              },
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'ضيف الوزارة');
      await tester.pumpAndSettle();

      captured
          .read(composerControllerProvider.notifier)
          .resetAfterConfirmedOrder();
      await tester.pumpAndSettle();

      // The field is the only part of the name the user can see. Left showing
      // a name the order will not carry, the button goes dead with an error
      // asking for a name that is visibly already there.
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, isEmpty);
    });
  });

  group('§1 — adding a second drink', () {
    testWidgets('the add action is on review, once there is a drink', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          CatalogueResponse(
            // Something of my own to add: after the buffet drink, "add
            // another" offers only that.
            drinks: [
              _item(1, 'قهوة', 'Drink'),
              _item(2, 'شاي', 'Drink', hasOwnStock: true, ownServingsLeft: 5),
            ],
            sugars: const [],
            extras: const [],
            locations: const [],
          ),
        ),
      );

      expect(find.text('أضف مشروبًا آخر'), findsNothing);

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();
      expect(find.text('أضف مشروبًا آخر'), findsOneWidget);
    });

    testWidgets('the buffet cap warns but leaves the order button live', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          CatalogueResponse(
            // My own tea, but the jar reads empty: the line falls back to
            // buffet stock, which is a stock reading and so only warns.
            drinks: [
              _item(1, 'قهوة', 'Drink'),
              _item(2, 'شاي', 'Drink', hasOwnStock: true),
            ],
            sugars: const [],
            extras: const [],
            locations: const [],
          ),
        ),
      );

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أضف مشروبًا آخر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('شاي'));
      await tester.pumpAndSettle();

      // The second buffet drink cannot be ADDED, but it sits in the draft, so
      // the order carries two and the banner says why — on the drink's step,
      // where switching it to the user's own jar would fix it.
      expect(find.text('مشروب واحد فقط من البوفيه'), findsOneWidget);

      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();
      expect(find.text('مشروب واحد فقط من البوفيه'), findsOneWidget);

      // The warning explains; it does not bar the door. A line counts against
      // the cap when ownServingsLeft <= 0, which is a stock reading, and a
      // control switched off on a stock reading is forbidden outright.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'أرسل الطلب'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('the system navigation bar must not cover the order button', () {
    testWidgets('the footer clears a three-button navigation inset', (
      tester,
    ) async {
      // Android's three-button navigation draws a ~48dp strip over the bottom
      // of the app. Without clearance it sits on top of "Place order".
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding.zero;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _app(
          CatalogueResponse(
            drinks: [_item(1, 'قهوة', 'Drink')],
            sugars: const [],
            extras: const [],
            locations: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();

      final button = tester.getRect(
        find.widgetWithText(FilledButton, 'أرسل الطلب'),
      );
      final screenBottom = tester.getRect(find.byType(Scaffold)).bottom;

      // The button's bottom edge must sit above the inset, not under it.
      expect(button.bottom, lessThanOrEqualTo(screenBottom - 48));
    });
  });

  group('opened from a drink on Home', () {
    ComposerState stateOf(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(ComposerScreen)))
            .read(composerControllerProvider);

    final catalogue = CatalogueResponse(
      drinks: [
        _item(1, 'شاي', 'Drink'),
        _item(2, 'قهوة تركي', 'Drink', hasOwnStock: true, ownServingsLeft: 3),
      ],
      sugars: const [],
      extras: const [],
      locations: const [],
      maxLines: 3,
      maxBuffetDrinks: 1,
    );

    testWidgets('the tapped drink is chosen, from the jar its row stood for', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          catalogue,
          seed: const ComposerSeed(drinkItemId: 2, drinkFromOwn: true),
        ),
      );

      expect(stateOf(tester).drink?.itemId, 2);
      expect(stateOf(tester).drinkFromOwn, isTrue);
    });

    testWidgets('a drink retired since the tap is left unchosen', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(catalogue, seed: const ComposerSeed(drinkItemId: 99)),
      );

      expect(stateOf(tester).drink, isNull);
    });

    testWidgets('the seed is applied once, never over what the user picks', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(catalogue, seed: const ComposerSeed(drinkItemId: 2)),
      );
      ProviderScope.containerOf(tester.element(find.byType(ComposerScreen)))
          .read(composerControllerProvider.notifier)
          .selectDrink(catalogue.drinks.first);
      await tester.pumpAndSettle();

      // Rebuilds happen constantly; re-applying the seed on one would silently
      // undo what the user just picked.
      expect(stateOf(tester).drink?.itemId, 1);
    });
  });

  group('the three steps — Choose a drink, Drink Details, Review', () {
    CatalogueResponse menu() => CatalogueResponse(
      drinks: [
        _item(1, 'قهوة', 'Drink'),
        _item(2, 'نعناع', 'Drink', hasOwnStock: true, ownServingsLeft: 6),
      ],
      sugars: const [],
      extras: const [],
      locations: const [],
    );

    testWidgets('back steps back through the flow before it leaves', (
      tester,
    ) async {
      await _pumpTall(tester, _app(menu()));

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      expect(find.text('متابعة'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Back on Choose a drink, not out of the composer.
      expect(find.byType(ComposerScreen), findsOneWidget);
      expect(find.text('متابعة'), findsNothing);
      expect(find.text('قهوة'), findsOneWidget);
    });

    testWidgets('a favourite opens straight on Review', (tester) async {
      await _pumpTall(
        tester,
        _app(
          menu(),
          seed: ComposerSeed(
            favourite: FavouriteDto(
              favouriteId: 5,
              name: 'قهوتي',
              createdAtUtc: DateTime.utc(2026, 8, 24),
              lastUsedAtUtc: null,
              lines: const [
                OrderLineDto(
                  drinkItemId: 1,
                  drinkNameAr: 'قهوة',
                  sugarSpoons: 2,
                  variantId: null,
                  sugarItemId: null,
                  extraItemIds: [],
                  lineNote: null,
                  drinkFromOwn: false,
                  sugarFromOwn: false,
                  ownExtraItemIds: [],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('مراجعة الطلب'), findsOneWidget);
      expect(find.text('أرسل الطلب'), findsOneWidget);
    });

    testWidgets(
      'an own-jar drink offers a quantity, and its cups reach review',
      (tester) async {
        await _pumpTall(
          tester,
          _app(
            menu(),
            seed: const ComposerSeed(drinkItemId: 2, drinkFromOwn: true),
          ),
        );

        // Opened on the drink's step, with a stepper: the jar allows more than
        // one cup, where a single buffet drink would not.
        expect(find.text('الكمية'), findsOneWidget);
        await tester.tap(find.byTooltip('كوب إضافي'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('كوب إضافي'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('متابعة'));
        await tester.pumpAndSettle();

        // Three identical cups: one line on review, its stepper at three,
        // and three lines on the wire.
        expect(
          find.descendant(
            of: find.byType(QuantityStepper),
            matching: find.text('3'),
          ),
          findsOneWidget,
        );
        expect(
          ProviderScope.containerOf(tester.element(find.byType(ComposerScreen)))
              .read(composerControllerProvider)
              .toRequest()
              .lines,
          hasLength(3),
        );
      },
    );

    testWidgets('a single buffet drink offers no quantity at all', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(menu(), seed: const ComposerSeed(drinkItemId: 1)),
      );

      expect(find.text('متابعة'), findsOneWidget);
      expect(find.text('الكمية'), findsNothing);
    });

    testWidgets(
      'an emptied review says why Place order is off, and leads back',
      (tester) async {
        await _pumpTall(
          tester,
          _app(menu(), seed: const ComposerSeed(drinkItemId: 1)),
        );
        await tester.tap(find.text('متابعة'));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('احذف هذا المشروب'));
        await tester.pumpAndSettle();

        // Disabled only because there is nothing to order — and the screen
        // says so, with the way back, so it is never an unexplained dead end.
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'أرسل الطلب'),
        );
        expect(button.onPressed, isNull);
        expect(find.text('لا يوجد مشروب في هذا الطلب'), findsOneWidget);

        await tester.tap(find.text('اختر مشروبًا'));
        await tester.pumpAndSettle();
        expect(find.text('قهوة'), findsWidgets);
      },
    );

    testWidgets('clearing the draft never leaves a blank step behind it', (
      tester,
    ) async {
      // Opened on the drink's step: once that drink is removed, back must not
      // land on a Drink Details with no drink to show.
      await _pumpTall(
        tester,
        _app(menu(), seed: const ComposerSeed(drinkItemId: 1)),
      );
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('احذف هذا المشروب'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('اختر مشروبًا'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('مراجعة الطلب'), findsOneWidget);
    });

    testWidgets(
      'back after "add another" returns to the order, not out of it',
      (tester) async {
        await _pumpTall(
          tester,
          _app(menu(), seed: const ComposerSeed(drinkItemId: 1)),
        );
        await tester.tap(find.text('متابعة'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('أضف مشروبًا آخر'));
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // Every drink already added is still there to place.
        expect(find.text('مراجعة الطلب'), findsOneWidget);
        expect(find.text('أرسل الطلب'), findsOneWidget);
      },
    );

    testWidgets(
      '"add another" after the buffet drink lists own materials only',
      (tester) async {
        await _pumpTall(
          tester,
          _app(menu(), seed: const ComposerSeed(drinkItemId: 1)),
        );
        await tester.tap(find.text('متابعة'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('أضف مشروبًا آخر'));
        await tester.pumpAndSettle();

        // Said, not just missing: the buffet is gone for a reason.
        expect(find.text('من موادك فقط'), findsOneWidget);
        expect(find.text('نعناع'), findsOneWidget);
        expect(find.text('قهوة'), findsNothing);
      },
    );

    testWidgets('no own materials: no "add another", and Review says why', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          CatalogueResponse(
            drinks: [_item(1, 'قهوة', 'Drink')],
            sugars: const [],
            extras: const [],
            locations: const [],
          ),
          seed: const ComposerSeed(drinkItemId: 1),
        ),
      );
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();

      expect(find.text('أضف مشروبًا آخر'), findsNothing);
      expect(
        find.text(
          'مشروب واحد فقط من البوفيه في كل طلب، والمزيد يكون من موادك.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a first drink from my own jar leaves the buffet on offer', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          menu(),
          seed: const ComposerSeed(drinkItemId: 2, drinkFromOwn: true),
        ),
      );
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أضف مشروبًا آخر'));
      await tester.pumpAndSettle();

      expect(find.text('من موادك فقط'), findsNothing);
      expect(find.text('قهوة'), findsOneWidget);
    });

    testWidgets('a favourite whose drink was retired opens on the drink list', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(menu(), seed: ComposerSeed(favourite: _favouriteOf(99))),
      );

      expect(find.text('مراجعة الطلب'), findsNothing);
      expect(find.text('قهوة'), findsWidgets);
    });
  });

  // The catalogue reads the account on every fetch; the sign-in value is a
  // 30-day token claim. A revocation since sign-in must not leave a guest
  // order the server now refuses.
  testWidgets('a guest privilege revoked since sign-in opens a self order', (
    tester,
  ) async {
    await _pumpTall(
      tester,
      _app(
        CatalogueResponse(
          drinks: [_item(1, 'قهوة', 'Drink')],
          sugars: const [],
          extras: const [],
          locations: const [],
          canOrderForGuests: false,
        ),
        canOrderForGuests: true,
        mode: OrderMode.guest,
      ),
    );

    expect(find.text('اسم الضيف'), findsNothing);
    expect(find.text('طلب لضيف'), findsNothing);
  });

  group('a guest order cannot move on without its guest', () {
    CatalogueResponse menu() => CatalogueResponse(
      drinks: [_item(1, 'قهوة', 'Drink')],
      sugars: const [],
      extras: const [],
      locations: const [],
    );

    testWidgets('a favourite tapped without the name shows why, and waits', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          menu(),
          canOrderForGuests: true,
          mode: OrderMode.guest,
          favourites: [_favouriteOf(1)],
        ),
      );

      await tester.tap(find.textContaining('قهوتي'));
      await tester.pumpAndSettle();

      expect(find.text('اكتب اسم الضيف لإتمام الطلب.'), findsOneWidget);
      expect(find.text('مراجعة الطلب'), findsNothing);
    });

    testWidgets('Place order without the name goes back to the field', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(menu(), canOrderForGuests: true, mode: OrderMode.guest),
      );
      await tester.enterText(find.byType(TextField).first, 'وفد الوزارة');
      await tester.pumpAndSettle();
      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();

      // The name goes missing after the fact (a revoked privilege nulls it).
      ProviderScope.containerOf(tester.element(find.byType(ComposerScreen)))
          .read(composerControllerProvider.notifier)
          .setOnBehalfOfName(null);
      await tester.pumpAndSettle();

      // The button is live, and tapping it shows what is missing, where it
      // can be fixed — not a dead control that says nothing.
      await tester.tap(find.text('أرسل الطلب'));
      await tester.pumpAndSettle();
      expect(find.text('اكتب اسم الضيف لإتمام الطلب.'), findsOneWidget);
    });
  });

  group('a staff member\'s own order', () {
    testWidgets('pops back to the queue with its outcome, from any step', (
      tester,
    ) async {
      Object? result;
      final router = GoRouter(
        initialLocation: '/queue',
        routes: [
          GoRoute(
            path: '/queue',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await context.push<Object?>('/order');
                },
                child: const Text('open'),
              ),
            ),
          ),
          GoRoute(
            path: '/order',
            builder: (context, state) => const ComposerScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);

      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogueProvider.overrideWith(
              (ref) async => CatalogueResponse(
                drinks: [_item(1, 'قهوة', 'Drink')],
                sugars: const [],
                extras: const [],
                locations: const [],
              ),
            ),
            favouritesProvider.overrideWith(
              (ref) async => const FavouritesResponse(favourites: []),
            ),
            canOrderForGuestsProvider.overrideWith((ref) => false),
            // A staff member: their own order is made and handed over at once,
            // so they are never asked pickup or delivery.
            authControllerProvider.overrideWith(
              (ref) => FakeAuthController(
                const AuthState(
                  stage: AuthStage.signedIn,
                  restoredIdentity: (
                    role: 'Staff',
                    displayName: 'أحمد',
                    department: 'البوفيه',
                    canOrderForGuests: false,
                  ),
                ),
                pinned: true,
              ),
            ),
            catalogueRepositoryProvider.overrideWithValue(_AutoServing()),
          ],
          child: MaterialApp.router(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابعة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أرسل الطلب'));
      await tester.pumpAndSettle();

      // Three steps deep, and still one pop: back at the queue, with the
      // outcome to show, not stranded on an earlier step.
      expect(find.byType(ComposerScreen), findsNothing);
      expect(result, isA<SelfOrderOutcome>());
      expect((result! as SelfOrderOutcome).orderId, 77);
    });
  });
}

/// A favourite with one line, for drink [drinkId].
FavouriteDto _favouriteOf(int drinkId) => FavouriteDto(
  favouriteId: 5,
  name: 'قهوتي',
  createdAtUtc: DateTime.utc(2026, 8, 24),
  lastUsedAtUtc: null,
  lines: [
    OrderLineDto(
      drinkItemId: drinkId,
      drinkNameAr: 'قهوة',
      sugarSpoons: 1,
      variantId: null,
      sugarItemId: null,
      extraItemIds: const [],
      lineNote: null,
      drinkFromOwn: false,
      sugarFromOwn: false,
      ownExtraItemIds: const [],
    ),
  ],
);

/// Serves a staff member's own order immediately, as the server does.
class _AutoServing extends CatalogueRepository {
  _AutoServing() : super(Dio());

  @override
  Future<PlaceOrderResponse> placeOrder({
    required PlaceOrderApiRequest request,
    required String languageCode,
    required String networkErrorFallback,
  }) async =>
      const PlaceOrderResponse(orderId: 77, duplicate: false, autoServed: true);
}
