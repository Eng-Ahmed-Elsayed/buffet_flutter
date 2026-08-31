import 'package:buffet_app/data/models/auth_models.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/order/composer_controller.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/order_mode.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

Widget _app(
  CatalogueResponse catalogue, {
  bool canOrderForGuests = false,
  OrderMode mode = OrderMode.self,
}) => ProviderScope(
  overrides: [
    catalogueProvider.overrideWith((ref) async => catalogue),
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
    home: ComposerScreen(seed: ComposerSeed(mode: mode)),
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
              usual: null,
            ),
          ),
        );

        expect(find.text('من موادي'), findsOneWidget);
        expect(find.text('من البوفيه'), findsOneWidget);
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
              usual: null,
            ),
          ),
        );

        expect(find.text('من موادي'), findsOneWidget);
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
            usual: null,
          ),
        ),
      );

      expect(find.text('من موادي'), findsNothing);
      expect(find.text('من البوفيه'), findsNothing);
      expect(find.text('قهوة'), findsOneWidget);
    });
  });

  group('§6 — the extras row follows the selected drink', () {
    testWidgets('every extra shows before a drink is chosen', (tester) async {
      await _pumpTall(
        tester,
        _app(
          CatalogueResponse(
            drinks: [_item(1, 'قهوة', 'Drink')],
            sugars: const [],
            extras: [_item(9, 'حليب', 'Extra'), _item(10, 'قرفة', 'Extra')],
            locations: const [],
            usual: null,
          ),
        ),
      );

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
            usual: null,
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
            usual: null,
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
      usual: null,
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

      // And the order button never goes off for it.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'أرسل الطلب'),
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
      usual: null,
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
      expect(find.text('الطلب لضيف'), findsNothing);
    });

    testWidgets('a guest order asks who it is for, first', (tester) async {
      await _pumpTall(
        tester,
        _app(oneDrink(), canOrderForGuests: true, mode: OrderMode.guest),
      );

      // Both the header and the field label carry the phrase.
      expect(find.text('الطلب لضيف'), findsWidgets);

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
      expect(find.text('الطلب لضيف'), findsNothing);
    });

    testWidgets('the order button stays live so the error can be shown', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(oneDrink(), canOrderForGuests: true, mode: OrderMode.guest),
      );

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();

      // A guest order with no name cannot be sent — but the button is NOT
      // dead. Tapping it reveals what is missing, rather than leaving the user
      // with a control that does nothing and says nothing.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'أرسل الطلب'),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(find.text('أرسل الطلب'));
      await tester.pumpAndSettle();

      expect(find.text('اكتب اسم الضيف لإتمام الطلب.'), findsOneWidget);
    });
  });

  group('the usual order is one tap from the ordering screen (§12)', () {
    CatalogueResponse withUsual() => CatalogueResponse(
      drinks: [_item(1, 'قهوة', 'Drink')],
      sugars: const [],
      extras: const [],
      locations: const [],
      usual: const UsualOrderDto(summary: 'قهوة بدون سكر', lines: []),
    );

    testWidgets('it is offered on the composer itself', (tester) async {
      await _pumpTall(tester, _app(withUsual()));

      // It lives on the hub too, but staff reach this screen by pushing it
      // from the queue and never see the hub — so a usual that existed only
      // there took the feature away from them entirely.
      expect(find.text('اطلب مرة أخرى'), findsOneWidget);
    });

    testWidgets('it steps aside once a drink has been added', (tester) async {
      await _pumpTall(tester, _app(withUsual()));

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أضف مشروبًا آخر'));
      await tester.pumpAndSettle();

      // Replacing drinks the user has already chosen is not a "repeat".
      expect(find.text('اطلب مرة أخرى'), findsNothing);
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
            usual: null,
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
                usual: null,
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
    testWidgets('the add action appears only once a drink is chosen', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          CatalogueResponse(
            drinks: [_item(1, 'قهوة', 'Drink'), _item(2, 'شاي', 'Drink')],
            sugars: const [],
            extras: const [],
            locations: const [],
            usual: null,
          ),
        ),
      );

      expect(find.text('أضف مشروبًا آخر'), findsNothing);

      await tester.tap(find.text('قهوة'));
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
            drinks: [_item(1, 'قهوة', 'Drink'), _item(2, 'شاي', 'Drink')],
            sugars: const [],
            extras: const [],
            locations: const [],
            usual: null,
          ),
        ),
      );

      await tester.tap(find.text('قهوة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أضف مشروبًا آخر'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('شاي'));
      await tester.pumpAndSettle();

      // The second buffet drink cannot be ADDED — the add button refuses it —
      // but it still sits in the draft, so the order carries two and the
      // banner says why.
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
            usual: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.getRect(
        find.widgetWithText(FilledButton, 'أرسل الطلب'),
      );
      final screenBottom = tester.getRect(find.byType(Scaffold)).bottom;

      // The button's bottom edge must sit above the inset, not under it.
      expect(button.bottom, lessThanOrEqualTo(screenBottom - 48));
    });
  });
}
