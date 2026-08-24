import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
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

const _catalogue = CatalogueResponse(
  drinks: [
    CatalogueItemDto(
      itemId: 1,
      nameAr: 'شاي',
      nameEn: '',
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
  usual: null,
  maxLines: 3,
  maxBuffetDrinks: 2,
);

Widget _app(List<OrderSummaryDto> orders) => ProviderScope(
  overrides: [
    catalogueProvider.overrideWith((ref) async => _catalogue),
    canOrderForGuestsProvider.overrideWith((ref) => false),
    myOrdersProvider.overrideWith((ref) async => orders),
  ],
  child: const MaterialApp(
    locale: Locale('ar'),
    supportedLocales: [Locale('ar'), Locale('en')],
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: ComposerScreen(),
  ),
);

Future<void> _pumpTall(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

// The Arabic strings, as they appear in `app_ar.arb`.
const _readyTitle = 'مشروبك جاهز';
const _liveTitle = 'لديك طلب قيد التنفيذ';

void main() {
  group('an uncollected order is visible on the screen the user lands on', () {
    testWidgets('a Ready order announces itself on the composer', (
      tester,
    ) async {
      await _pumpTall(tester, _app([_order(7, 'Ready')]));

      expect(find.text(_readyTitle), findsOneWidget);
    });

    testWidgets('a Pending order shows the in-progress wording', (
      tester,
    ) async {
      await _pumpTall(tester, _app([_order(7, 'Pending')]));

      expect(find.text(_liveTitle), findsOneWidget);
      expect(find.text(_readyTitle), findsNothing);
    });

    testWidgets('InProgress counts as outstanding too', (tester) async {
      await _pumpTall(tester, _app([_order(7, 'InProgress')]));

      expect(find.text(_liveTitle), findsOneWidget);
    });

    testWidgets('Ready leads even when a newer order is still pending', (
      tester,
    ) async {
      // A drink standing on the counter needs the user more than one still
      // being made, whatever order the server listed them in.
      await _pumpTall(tester, _app([_order(9, 'Pending'), _order(7, 'Ready')]));

      expect(find.text(_readyTitle), findsOneWidget);
      expect(find.text(_liveTitle), findsNothing);
    });

    testWidgets('the remaining outstanding orders are summarised in one line', (
      tester,
    ) async {
      await _pumpTall(
        tester,
        _app([
          _order(9, 'Pending'),
          _order(8, 'InProgress'),
          _order(7, 'Ready'),
        ]),
      );

      // Two beyond the one the card leads with — the dual, in Arabic.
      expect(find.text('طلبان آخران ما زالا قائمين'), findsOneWidget);
    });

    testWidgets('a single outstanding order carries no "more" line', (
      tester,
    ) async {
      await _pumpTall(tester, _app([_order(7, 'Ready')]));

      expect(find.textContaining('ما زال'), findsNothing);
    });

    testWidgets('settled orders leave the composer alone', (tester) async {
      // Completed and Cancelled are the only terminal states — neither is
      // owed to anyone, so neither earns the top of the screen.
      await _pumpTall(
        tester,
        _app([_order(9, 'Completed'), _order(8, 'Cancelled')]),
      );

      expect(find.text(_readyTitle), findsNothing);
      expect(find.text(_liveTitle), findsNothing);
    });

    testWidgets('no orders at all means no card', (tester) async {
      await _pumpTall(tester, _app([]));

      expect(find.text(_readyTitle), findsNothing);
      expect(find.text(_liveTitle), findsNothing);
    });
  });
}
