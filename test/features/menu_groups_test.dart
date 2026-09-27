import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/features/order/widgets/drink_menu.dart';
import 'package:buffet_app/features/order/widgets/menu_item_row.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

final _ar = lookupAppLocalizations(const Locale('ar'));

CatalogueItemDto _drink(
  int id,
  String name, {
  int? group,
  String? description,
  bool own = false,
}) => CatalogueItemDto(
  itemId: id,
  nameAr: name,
  nameEn: '',
  category: 'Drink',
  unit: 'جرام',
  imageUrl: null,
  inStock: true,
  hasOwnStock: own,
  ownServingsLeft: own ? 5 : 0,
  variants: const [],
  allowedExtraItemIds: null,
  drinkGroupId: group,
  descriptionAr: description,
);

const _coffee = DrinkGroupDto(
  drinkGroupId: 1,
  nameAr: 'قهوة',
  nameEn: 'Coffee',
  sortOrder: 1,
);
const _tea = DrinkGroupDto(
  drinkGroupId: 2,
  nameAr: 'شاي',
  nameEn: 'Tea',
  sortOrder: 2,
);

Future<void> _pump(
  WidgetTester tester,
  List<CatalogueItemDto> drinks, {
  List<DrinkGroupDto> groups = const [],
  String query = '',
}) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DrinkMenu(
            drinks: drinks,
            groups: groups,
            query: query,
            onSelect: (_, {required fromOwn}) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _row(String name) => find.widgetWithText(MenuItemRow, name);

/// Chip labels are bidi-isolated (admin-entered, either script).
Finder _chip(String label) => find.ancestor(
  of: find.textContaining(label),
  matching: find.byType(ChoiceChip),
);

void main() {
  setUpAll(loadAppFonts);

  final drinks = [
    _drink(1, 'تركي', group: 1, own: true),
    _drink(2, 'نسكافيه', group: 1),
    _drink(3, 'شاي أحمر', group: 2),
    _drink(4, 'كركديه'),
    // Filed under a group the catalogue no longer lists: counts as none.
    _drink(5, 'ينسون', group: 9),
  ];

  testWidgets('groups filter the menu, keeping «من موادي» first', (
    tester,
  ) async {
    await _pump(tester, drinks, groups: const [_coffee, _tea]);

    for (final label in [_ar.menuGroupAll, 'قهوة', 'شاي', _ar.menuGroupOther]) {
      expect(_chip(label), findsOneWidget);
    }
    // All: every drink, the owned one under both jars.
    expect(_row('تركي'), findsNWidgets(2));
    expect(_row('ينسون'), findsOneWidget);

    await tester.tap(_chip('قهوة'));
    await tester.pump();
    expect(_row('نسكافيه'), findsOneWidget);
    expect(_row('تركي'), findsNWidgets(2));
    expect(find.text(_ar.sectionMyMaterials), findsOneWidget);
    expect(_row('شاي أحمر'), findsNothing);

    await tester.tap(_chip(_ar.menuGroupOther));
    await tester.pump();
    expect(_row('كركديه'), findsOneWidget);
    expect(_row('ينسون'), findsOneWidget);
    expect(_row('نسكافيه'), findsNothing);
  });

  testWidgets('a search the chosen group empties says so, and offers the '
      'whole menu', (tester) async {
    await _pump(
      tester,
      drinks,
      groups: const [_coffee, _tea],
      query: 'شاي',
    );
    await tester.tap(_chip('قهوة'));
    await tester.pump();

    // Never "no drink by that name" for one a chip away.
    expect(find.text(_ar.noDrinkMatches), findsNothing);
    expect(find.textContaining('قهوة'), findsWidgets);
    await tester.tap(find.text(_ar.searchAllGroups));
    await tester.pump();
    expect(_row('شاي أحمر'), findsOneWidget);
  });

  testWidgets('no Other chip when every drink has a group', (tester) async {
    await _pump(
      tester,
      [_drink(1, 'تركي', group: 1), _drink(3, 'شاي أحمر', group: 2)],
      groups: const [_coffee, _tea],
    );
    expect(_chip(_ar.menuGroupOther), findsNothing);
  });

  testWidgets('without groups, the chips jump to the two jars as before', (
    tester,
  ) async {
    await _pump(tester, drinks);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.widgetWithText(ActionChip, _ar.sectionMyMaterials), findsOne);
  });

  testWidgets('a row shows the description when there is one', (
    tester,
  ) async {
    await _pump(tester, [
      _drink(1, 'تركي', description: 'قهوة محوّجة بالهيل'),
      _drink(2, 'شاي'),
    ]);
    expect(find.text('قهوة محوّجة بالهيل'), findsOneWidget);
  });
}
