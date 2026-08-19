import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/features/order/widgets/drink_tile.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogueItemDto item({
  String nameAr = 'قهوة',
  String nameEn = 'Coffee',
  bool hasOwnStock = false,
  int ownServingsLeft = 0,
}) => CatalogueItemDto(
  itemId: 1,
  nameAr: nameAr,
  nameEn: nameEn,
  category: 'Drink',
  unit: 'جرام',
  imageUrl: null,
  inStock: true,
  hasOwnStock: hasOwnStock,
  ownServingsLeft: ownServingsLeft,
  variants: const [],
);

Widget wrap(Widget child, {Locale locale = const Locale('ar')}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('ar'), Locale('en')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

/// The tile's own border colour, read off the decoration it builds.
Color borderColourOf(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer),
  );
  final decoration = container.decoration! as BoxDecoration;
  return decoration.border!.top.color;
}

void main() {
  group('DrinkTile — violet means "from my own jar", nothing else', () {
    testWidgets('a SELECTED tile does not use violet', (tester) async {
      // Rule 3: never reuse accent for generic selection. Doing so makes the
      // violet servings label on this very tile ambiguous — the one place
      // where ownership has to be unmistakable.
      await tester.pumpWidget(
        wrap(DrinkTile(item: item(), selected: true, onTap: () {})),
      );

      expect(borderColourOf(tester), isNot(BrandColors.accent));
      expect(borderColourOf(tester), BrandColors.brand);
    });

    testWidgets('an unselected tile is a hairline in brandLight', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(DrinkTile(item: item(), selected: false, onTap: () {})),
      );
      expect(borderColourOf(tester), BrandColors.brandLight);
    });

    testWidgets('violet IS used for the own-stock servings label', (
      tester,
    ) async {
      // The positive half of the rule: where the user genuinely owns stock,
      // violet is exactly right.
      await tester.pumpWidget(
        wrap(
          DrinkTile(
            item: item(hasOwnStock: true, ownServingsLeft: 3),
            selected: false,
            onTap: () {},
          ),
        ),
      );

      final labels = tester.widgetList<Text>(find.byType(Text));
      final violet = labels.where((t) => t.style?.color == BrandColors.accent);
      expect(violet, isNotEmpty);
    });

    testWidgets('a depleted own jar warns rather than reading as unavailable', (
      tester,
    ) async {
      // Shortages never block: the tile still taps, it just warns.
      await tester.pumpWidget(
        wrap(
          DrinkTile(
            item: item(hasOwnStock: true, ownServingsLeft: 0),
            selected: false,
            onTap: () {},
          ),
        ),
      );

      final labels = tester.widgetList<Text>(find.byType(Text));
      expect(
        labels.where((t) => t.style?.color == BrandColors.warning),
        isNotEmpty,
      );
    });
  });

  group('DrinkTile — bilingual names', () {
    testWidgets('shows the English name in the English locale', (tester) async {
      await tester.pumpWidget(
        wrap(
          DrinkTile(item: item(), selected: false, onTap: () {}),
          locale: const Locale('en'),
        ),
      );
      expect(find.text('Coffee'), findsOneWidget);
    });

    testWidgets('shows the Arabic name in the Arabic locale', (tester) async {
      await tester.pumpWidget(
        wrap(DrinkTile(item: item(), selected: false, onTap: () {})),
      );
      expect(find.text('قهوة'), findsOneWidget);
    });

    testWidgets('falls back to Arabic when there is no English name', (
      tester,
    ) async {
      // كركديه has no nameEn on the live server. An English user sees the
      // Arabic name rather than a blank tile.
      await tester.pumpWidget(
        wrap(
          DrinkTile(
            item: item(nameAr: 'كركديه', nameEn: ''),
            selected: false,
            onTap: () {},
          ),
          locale: const Locale('en'),
        ),
      );
      expect(find.text('كركديه'), findsOneWidget);
    });
  });
}
