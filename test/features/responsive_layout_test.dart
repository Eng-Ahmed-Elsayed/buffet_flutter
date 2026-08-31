@TestOn('vm')
library;

/// Every screen must fit the narrowest phone it will meet, at every text scale
/// the platform can hand it.
///
/// This file exists because four separate overflows shipped without one: the
/// home action grid and the composer's drink grid both fixed a tile HEIGHT via
/// childAspectRatio, so a label needing more room overflowed rather than
/// growing — at the DEFAULT text scale, not merely at the accessibility ones.
/// The usual-order heading and the orders list's status word did the same
/// horizontally at 2x.
///
/// 320dp is the floor: it is the narrowest width Android reports on a phone in
/// portrait, and Arabic is checked alongside English because the two wrap at
/// different lengths.
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/home/home_screen.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:buffet_app/features/order/order_mode.dart';
import 'package:buffet_app/features/settings/settings_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogueItemDto _d(int id, String n) => CatalogueItemDto(
  itemId: id,
  nameAr: n,
  nameEn: n,
  category: 'Drink',
  unit: 'ج',
  imageUrl: null,
  inStock: true,
  hasOwnStock: id == 2,
  ownServingsLeft: 0,
  variants: const [],
  allowedExtraItemIds: null,
);

final _cat = CatalogueResponse(
  drinks: [_d(1, 'قهوة تركي سادة'), _d(2, 'شاي بالنعناع')],
  sugars: const [],
  extras: const [],
  locations: const [],
  usual: const UsualOrderDto(summary: 'قهوة تركي سادة (بدون سكر)', lines: []),
  maxLines: 5,
  maxBuffetDrinks: 1,
);

final _orders = [
  OrderSummaryDto(
    orderId: 7,
    status: 'Ready',
    createdAtUtc: DateTime.utc(2026, 8, 20, 7),
    readyAtUtc: DateTime.utc(2026, 8, 20, 7, 5),
    handledAtUtc: null,
    locationText: 'الدور الثالث، مكتب ٣١٢',
    onBehalfOfName: 'ضيف الوزارة',
    notes: 'بدون لبن',
    lines: const [],
  ),
  OrderSummaryDto(
    orderId: 8,
    status: 'Completed',
    createdAtUtc: DateTime.utc(2026, 8, 19, 7),
    readyAtUtc: null,
    handledAtUtc: null,
    locationText: '',
    onBehalfOfName: null,
    notes: '',
    lines: const [],
  ),
];

Widget _wrap(Widget home, double scale, Locale locale) => ProviderScope(
  overrides: [
    catalogueProvider.overrideWith((r) async => _cat),
    canOrderForGuestsProvider.overrideWith((r) => true),
    myOrdersProvider.overrideWith((r) async => _orders),
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
    builder: (c, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: scale,
      maxScaleFactor: scale,
      child: child!,
    ),
    home: home,
  ),
);

void main() {
  final screens = <String, Widget>{
    'home': const HomeScreen(),
    'composer-self': const ComposerScreen(),
    'composer-guest': const ComposerScreen(
      seed: ComposerSeed(mode: OrderMode.guest),
    ),
    'my-orders': const MyOrdersScreen(),
    'settings': const SettingsScreen(),
  };

  for (final entry in screens.entries) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final locale in [const Locale('ar'), const Locale('en')]) {
        testWidgets('${entry.key} fits a 320dp phone at ${scale}x '
            'in ${locale.languageCode}', (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(_wrap(entry.value, scale, locale));
          await t.pumpAndSettle();
          // A RenderFlex overflow surfaces as a test exception. Every one of
          // these combinations used to raise one somewhere.
          expect(
            t.takeException(),
            isNull,
            reason:
                '${entry.key} overflows at ${scale}x in ${locale.languageCode}',
          );
        });
      }
    }
  }
}
