import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OrderLineDto _line({int drink = 4, int spoons = 2}) => OrderLineDto(
  drinkItemId: drink,
  drinkNameAr: 'قهوة',
  sugarSpoons: spoons,
  variantId: null,
  sugarItemId: null,
  extraItemIds: const <int>[],
  lineNote: null,
  drinkFromOwn: false,
  sugarFromOwn: false,
  ownExtraItemIds: const <int>[],
);

OrderSummaryDto _order({
  int id = 41,
  String status = 'Completed',
  List<OrderLineDto>? lines,
}) => OrderSummaryDto(
  orderId: id,
  status: status,
  createdAtUtc: DateTime.utc(2026, 8, 19, 8),
  readyAtUtc: null,
  handledAtUtc: null,
  locationText: 'مكتبي',
  onBehalfOfName: null,
  notes: '',
  lines: lines ?? [_line()],
);

FavouriteDto _favourite({List<OrderLineDto>? lines}) => FavouriteDto(
  favouriteId: 1,
  name: 'قهوة الصبح',
  createdAtUtc: DateTime.utc(2026, 8, 24),
  lastUsedAtUtc: null,
  lines: lines ?? [_line()],
);

Widget _app({
  required List<OrderSummaryDto> orders,
  List<FavouriteDto> favourites = const [],
}) => ProviderScope(
  overrides: [
    myOrdersProvider.overrideWith((ref) async => orders),
    favouritesProvider.overrideWith(
      (ref) async => FavouritesResponse(favourites: favourites),
    ),
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
    home: MyOrdersScreen(),
  ),
);

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

void main() {
  group('saving a past order asks what to call it', () {
    testWidgets('tapping save opens a name dialog rather than saving at once', (
      tester,
    ) async {
      await _pump(tester, _app(orders: [_order()]));

      await tester.tap(find.text('احفظ كطلب مفضل'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('الاسم (اختياري)'), findsOneWidget);
    });

    testWidgets('the save action stays enabled with the field empty', (
      tester,
    ) async {
      // Blank is an ordinary choice — the server names it after the drinks —
      // so demanding a name would turn a one-tap action into a typing task.
      await _pump(tester, _app(orders: [_order()]));

      await tester.tap(find.text('احفظ كطلب مفضل'));
      await tester.pumpAndSettle();

      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'حفظ'),
      );
      expect(save.onPressed, isNotNull);
    });

    testWidgets('cancelling the dialog saves nothing', (tester) async {
      await _pump(tester, _app(orders: [_order()]));

      await tester.tap(find.text('احفظ كطلب مفضل'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      // Still offered, so nothing was recorded.
      expect(find.text('احفظ كطلب مفضل'), findsOneWidget);
    });
  });

  group('an order already saved says so instead of offering again', () {
    testWidgets('a matching favourite replaces the action with a statement', (
      tester,
    ) async {
      await _pump(tester, _app(orders: [_order()], favourites: [_favourite()]));

      expect(find.text('محفوظ في المفضلة'), findsOneWidget);
      // Replaced, not disabled: a greyed control with no reason is a dead end.
      expect(find.text('احفظ كطلب مفضل'), findsNothing);
    });

    testWidgets('a different order still offers to save', (tester) async {
      await _pump(
        tester,
        _app(
          orders: [
            _order(lines: [_line(spoons: 1)]),
          ],
          favourites: [_favourite()],
        ),
      );

      expect(find.text('احفظ كطلب مفضل'), findsOneWidget);
      expect(find.text('محفوظ في المفضلة'), findsNothing);
    });

    testWidgets('an order with no lines is not offered at all', (tester) async {
      // The server refuses an empty favourite with a 400, so offering the
      // action here would take the user through a naming dialog to reach a
      // guaranteed rejection. The backend guards against zero-line orders
      // explicitly, so they exist.
      await _pump(tester, _app(orders: [_order(lines: const [])]));

      expect(find.text('احفظ كطلب مفضل'), findsNothing);
      expect(find.text('محفوظ في المفضلة'), findsNothing);
      // Anchored: the row itself is on screen.
      expect(find.textContaining('مكتبي'), findsOneWidget);
    });

    testWidgets('a live order offers neither — it is not finished yet', (
      tester,
    ) async {
      await _pump(tester, _app(orders: [_order(status: 'Pending')]));

      expect(find.text('احفظ كطلب مفضل'), findsNothing);
      expect(find.text('محفوظ في المفضلة'), findsNothing);
      // Anchored on something that IS expected, so this cannot pass on a
      // blank screen. textContaining, because the location is bidi-isolated
      // (§2.4) and so is not equal to the bare string.
      expect(find.textContaining('مكتبي'), findsOneWidget);
      expect(find.text('قيد التنفيذ'), findsOneWidget);
    });
  });
}
