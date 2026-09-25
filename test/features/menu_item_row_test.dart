import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/features/order/widgets/menu_item_row.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

CatalogueItemDto _drink({
  String nameAr = 'قهوة تركي',
  String nameEn = 'Turkish coffee',
  bool inStock = true,
  bool hasOwnStock = false,
  int ownServingsLeft = 0,
}) => CatalogueItemDto(
  itemId: 1,
  nameAr: nameAr,
  nameEn: nameEn,
  category: 'Drink',
  unit: 'جرام',
  imageUrl: null,
  inStock: inStock,
  hasOwnStock: hasOwnStock,
  ownServingsLeft: ownServingsLeft,
  variants: const [],
  allowedExtraItemIds: null,
);

Future<void> _pump(
  WidgetTester tester,
  CatalogueItemDto drink, {
  bool fromOwn = false,
  VoidCallback? onTap,
  Locale locale = const Locale('ar'),
}) async {
  await tester.pumpWidget(
    testApp(
      locale: locale,
      home: Scaffold(
        body: MenuItemRow(
          drink: drink,
          fromOwn: fromOwn,
          onTap: onTap ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

Color? _colourOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

/// The menu row carries the rules the old drink tile did: violet means "from
/// my own jar", a shortage warns and never blocks, and names follow the
/// locale.
void main() {
  group('violet means "from my own jar", nothing else', () {
    testWidgets('the own-jar row shows its servings in violet', (tester) async {
      await _pump(
        tester,
        _drink(hasOwnStock: true, ownServingsLeft: 4),
        fromOwn: true,
      );

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(_colourOf(tester, l10n.servingsLeft(4)), BrandColors.accent);
    });

    testWidgets('a depleted own jar warns rather than reading as unavailable', (
      tester,
    ) async {
      await _pump(tester, _drink(hasOwnStock: true), fromOwn: true);

      final servings = find.textContaining('متبق');
      expect(servings, findsNothing, reason: 'none left reads as a word');
      final label = tester
          .widgetList<Text>(find.byType(Text))
          .firstWhere((t) => t.style?.color == BrandColors.warning);
      expect(label.data, isNotEmpty);
    });

    testWidgets('the buffet row of an owned drink carries no violet', (
      tester,
    ) async {
      await _pump(tester, _drink(hasOwnStock: true, ownServingsLeft: 4));

      final colours = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.style?.color);
      expect(colours, isNot(contains(BrandColors.accent)));
    });
  });

  group('out of stock warns and never blocks', () {
    testWidgets('the badge is shown in the warning colours', (tester) async {
      await _pump(tester, _drink(inStock: false));

      expect(_colourOf(tester, 'نفد من البوفيه'), BrandColors.warning);
    });

    testWidgets('and the row still taps', (tester) async {
      var tapped = false;
      await _pump(tester, _drink(inStock: false), onTap: () => tapped = true);

      await tester.tap(find.byType(MenuItemRow));
      expect(tapped, isTrue);
    });
  });

  group('bilingual names', () {
    testWidgets('English in the English locale', (tester) async {
      await _pump(tester, _drink(), locale: const Locale('en'));
      expect(find.text('Turkish coffee'), findsOneWidget);
    });

    testWidgets('Arabic in the Arabic locale', (tester) async {
      await _pump(tester, _drink());
      expect(find.text('قهوة تركي'), findsOneWidget);
    });

    testWidgets('falls back to Arabic when there is no English name', (
      tester,
    ) async {
      await _pump(tester, _drink(nameEn: ''), locale: const Locale('en'));
      expect(find.text('قهوة تركي'), findsOneWidget);
    });
  });
}
