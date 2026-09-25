import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/order/composer_controller.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
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
  variants: const [],
  allowedExtraItemIds: null,
);

final _menu = CatalogueResponse(
  drinks: [_item(1, 'قهوة', 'Drink')],
  sugars: const [],
  extras: [
    _item(10, 'حليب', 'Extra', hasOwnStock: true, ownServingsLeft: 5),
    _item(11, 'قرفة', 'Extra'),
  ],
  locations: const [],
);

Widget _app() => ProviderScope(
  overrides: [
    catalogueProvider.overrideWith((ref) async => _menu),
    favouritesProvider.overrideWith(
      (ref) async => const FavouritesResponse(favourites: []),
    ),
    canOrderForGuestsProvider.overrideWith((ref) => false),
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
    home: ComposerScreen(seed: ComposerSeed(drinkItemId: 1)),
  ),
);

/// Rule 3: violet means "from my own jar". An extra's chip was violet whenever
/// the user owned some of it, while the order sent it as buffet stock — so the
/// colour claimed a source the order did not use.
void main() {
  group('an extra from my own jar is really sent from it', () {
    test('an owned extra ticked with fromOwn goes out in ownExtraItemIds', () {
      final c = ComposerController()
        ..selectDrink(_item(1, 'قهوة', 'Drink'), fromOwn: false)
        ..toggleExtra(10, fromOwn: true);

      final line = c.state.toRequest().lines.single;
      expect(line.extraItemIds, [10]);
      expect(line.ownExtraItemIds, [10]);
    });

    test('switching it to the buffet keeps the extra, drops the jar', () {
      final c = ComposerController()
        ..selectDrink(_item(1, 'قهوة', 'Drink'), fromOwn: false)
        ..toggleExtra(10, fromOwn: true)
        ..setExtraFromOwn(10, false);

      final line = c.state.toRequest().lines.single;
      expect(line.extraItemIds, [10]);
      expect(line.ownExtraItemIds, isEmpty);
    });

    test('an extra that is not ticked cannot be sourced from a jar', () {
      final c = ComposerController()
        ..selectDrink(_item(1, 'قهوة', 'Drink'), fromOwn: false)
        ..setExtraFromOwn(10, true);

      expect(c.state.ownExtraItemIds, isEmpty);
    });

    test('unticking an extra forgets its jar', () {
      final c = ComposerController()
        ..selectDrink(_item(1, 'قهوة', 'Drink'), fromOwn: false)
        ..toggleExtra(10, fromOwn: true)
        ..toggleExtra(10);

      expect(c.state.extraItemIds, isEmpty);
      expect(c.state.ownExtraItemIds, isEmpty);
    });
  });

  group('Drink Details says which jar an owned extra comes from', () {
    testWidgets('ticking it draws from my jar, and the row switches it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      ComposerState state() =>
          ProviderScope.containerOf(tester.element(find.byType(ComposerScreen)))
              .read(composerControllerProvider);

      // No source row until an owned extra is ticked: nothing to decide yet.
      expect(find.text(l10n.sectionMyMaterials), findsNothing);

      await tester.tap(find.text('حليب'));
      await tester.pumpAndSettle();
      expect(state().ownExtraItemIds, {10});
      expect(find.text(l10n.sectionMyMaterials), findsOneWidget);

      await tester.tap(find.text(l10n.sectionBuffet));
      await tester.pumpAndSettle();
      expect(state().extraItemIds, {10});
      expect(state().ownExtraItemIds, isEmpty);
    });

    testWidgets('an extra the user does not own has no source row', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      await tester.tap(find.text('قرفة'));
      await tester.pumpAndSettle();

      expect(find.text(l10n.sectionMyMaterials), findsNothing);
    });
  });
}
