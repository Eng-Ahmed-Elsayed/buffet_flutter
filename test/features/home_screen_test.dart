import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/home/home_screen.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

CatalogueResponse _catalogue({UsualOrderDto? usual}) => CatalogueResponse(
  drinks: const [
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
  sugars: const [],
  extras: const [],
  locations: const [],
  usual: usual,
  maxLines: 3,
  maxBuffetDrinks: 1,
);

Widget _app({
  bool canOrderForGuests = false,
  List<OrderSummaryDto> orders = const [],
  UsualOrderDto? usual,
  Locale locale = const Locale('ar'),
}) => ProviderScope(
  overrides: [
    catalogueProvider.overrideWith((ref) async => _catalogue(usual: usual)),
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
    home: const HomeScreen(),
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
  group('the hub names every action the user may take', () {
    testWidgets('the everyday actions are all present', (tester) async {
      await _pumpTall(tester, _app());

      expect(find.text('طلب جديد'), findsOneWidget);
      expect(find.text('طلباتي'), findsOneWidget);
      expect(find.text('موادي'), findsOneWidget);
      expect(find.text('الإشعارات'), findsOneWidget);
      expect(find.text('الإعدادات'), findsOneWidget);
    });

    testWidgets('the guest action is absent without the privilege', (
      tester,
    ) async {
      await _pumpTall(tester, _app());

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

    testWidgets('the usual sits above the actions but below what is owed', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app(
          orders: [_order(7, 'Ready')],
          usual: const UsualOrderDto(summary: 'شاي', lines: []),
        ),
      );

      final outstandingY = tester.getTopLeft(find.text('مشروبك جاهز')).dy;
      final usualY = tester.getTopLeft(find.text('اطلب مرة أخرى')).dy;
      final newOrderY = tester.getTopLeft(find.text('طلب جديد')).dy;

      expect(outstandingY, lessThan(usualY));
      expect(usualY, lessThan(newOrderY));
    });

    testWidgets('no usual order means no repeat card', (tester) async {
      await _pumpTall(tester, _app());

      expect(find.text('اطلب مرة أخرى'), findsNothing);
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
