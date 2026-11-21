import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/order/composer_controller.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/order_mode.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

CatalogueItemDto _item(int id, String nameAr, String category) =>
    CatalogueItemDto(
      itemId: id,
      nameAr: nameAr,
      nameEn: '',
      category: category,
      unit: 'جرام',
      imageUrl: null,
      inStock: true,
      hasOwnStock: false,
      ownServingsLeft: 0,
      variants: const [],
      allowedExtraItemIds: null,
    );

/// Two sugars: the case where the server will not pick one itself, and drops
/// the spoons when the order names none.
final _menu = CatalogueResponse(
  drinks: [_item(1, 'قهوة', 'Drink')],
  sugars: [_item(20, 'سكر أبيض', 'Sugar'), _item(21, 'سكر بني', 'Sugar')],
  extras: const [],
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
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: ComposerScreen(seed: ComposerSeed(drinkItemId: 1)),
  ),
);

bool _selected(WidgetTester tester, String name) => tester
    .widget<ChoiceChip>(
      find.ancestor(of: find.text(name), matching: find.byType(ChoiceChip)),
    )
    .selected;

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(ComposerScreen)),
    );
  }

  testWidgets('the chip shown as chosen is the sugar the order sends', (
    tester,
  ) async {
    final container = await pump(tester);
    ComposerState state() => container.read(composerControllerProvider);

    // No sugar, no choice to make.
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(state().sugarItemId, 20);
    expect(_selected(tester, 'سكر أبيض'), isTrue);
    expect(_selected(tester, 'سكر بني'), isFalse);

    await tester.tap(find.text('سكر بني'));
    await tester.pumpAndSettle();
    final line = state().toRequest().lines.single;
    expect(line.sugarItemId, 21);
    expect(line.sugarSpoons, 1);
    expect(_selected(tester, 'سكر بني'), isTrue);

    // Back to none: the sugar goes with the spoons, so nothing stale is sent.
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(state().sugarItemId, isNull);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('spoons with no sugar (a replayed favourite) show no chip as '
      'chosen, rather than one the order omits', (tester) async {
    final container = await pump(tester);
    container.read(composerControllerProvider.notifier).setSugarSpoons(2);
    await tester.pumpAndSettle();

    expect(container.read(composerControllerProvider).sugarItemId, isNull);
    expect(_selected(tester, 'سكر أبيض'), isFalse);
    expect(_selected(tester, 'سكر بني'), isFalse);
  });
}
