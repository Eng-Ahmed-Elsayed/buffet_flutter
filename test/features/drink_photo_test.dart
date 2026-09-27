import 'dart:async';

import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/widgets/drink_photo.dart';
import 'package:buffet_app/features/order/widgets/favourites_strip.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/theme/brand_colors.dart';
import 'package:buffet_app/theme/dimens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Orders and favourites carry a drink's id but no picture, so the picture
// comes from the catalogue. A loading menu is a neutral frame, never the
// glyph, which would claim the drink has no picture.

const _url = 'https://example.test/uploads/items/coffee.jpg';

const _coffee = CatalogueItemDto(
  itemId: 1,
  nameAr: 'قهوة',
  nameEn: 'Coffee',
  category: 'Drink',
  unit: 'ج',
  imageUrl: _url,
  inStock: true,
  hasOwnStock: false,
  ownServingsLeft: 0,
  variants: [],
  allowedExtraItemIds: null,
);

const _menu = CatalogueResponse(
  drinks: [_coffee],
  sugars: [],
  extras: [],
  locations: [],
);

FavouriteDto _favourite({int drink = 1}) => FavouriteDto(
  favouriteId: 1,
  name: 'قهوة الصبح',
  createdAtUtc: DateTime.utc(2026, 8, 1),
  lastUsedAtUtc: null,
  lines: [
    OrderLineDto(
      drinkItemId: drink,
      drinkNameAr: 'قهوة',
      sugarSpoons: 0,
      variantId: null,
      sugarItemId: null,
      extraItemIds: const <int>[],
      lineNote: null,
      drinkFromOwn: false,
      sugarFromOwn: false,
      ownExtraItemIds: const <int>[],
    ),
  ],
);

Widget _app(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: child),
      ),
    );

/// The URL an [Image] loads, through the resize wrapper ItemImage adds.
String? _urlOf(Image image) {
  var provider = image.image;
  if (provider is ResizeImage) provider = provider.imageProvider;
  return provider is NetworkImage ? provider.url : null;
}

final _photo = find.byWidgetPredicate((w) => w is Image && _urlOf(w) == _url);

/// The neutral frame that holds the photo's place, at its full size.
Finder _frame(double size) => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.color == BrandColors.brandLight &&
      w.constraints?.maxWidth == size &&
      w.constraints?.maxHeight == size,
);

void main() {
  group('DrinkPhoto', () {
    testWidgets('shows the catalogue photo for the drink id', (tester) async {
      await tester.pumpWidget(
        _app(
          const DrinkPhoto(drinkItemId: 1, size: 44),
          overrides: [catalogueProvider.overrideWith((ref) async => _menu)],
        ),
      );
      await tester.pump();

      expect(_photo, findsOneWidget);
    });

    testWidgets('holds a neutral frame, not the glyph, while the menu loads', (
      tester,
    ) async {
      final pending = Completer<CatalogueResponse>();
      await tester.pumpWidget(
        _app(
          const DrinkPhoto(drinkItemId: 1, size: 44),
          overrides: [catalogueProvider.overrideWith((ref) => pending.future)],
        ),
      );
      await tester.pump();

      expect(_frame(44), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('a drink since retired from the menu gets the glyph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const DrinkPhoto(drinkItemId: 99, size: 44),
          overrides: [catalogueProvider.overrideWith((ref) async => _menu)],
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.byType(Icon), findsOneWidget);
    });
  });

  group('a favourite card pictures its drink', () {
    testWidgets('with the first drink photo from the menu', (tester) async {
      final favourite = _favourite();
      await tester.pumpWidget(
        _app(
          FavouriteCard(
            favourite: favourite,
            drink: FavouriteCard.drinkOf(favourite, _menu.drinks),
            fullWidth: true,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      );

      expect(_photo, findsOneWidget);
    });

    testWidgets('with a neutral frame while the menu loads', (tester) async {
      await tester.pumpWidget(
        _app(
          FavouriteCard(
            favourite: _favourite(),
            fullWidth: true,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      );

      expect(_frame(Dimens.imageThumb), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.replay), findsNothing);
    });

    testWidgets('in the strip the photo sits above the name, not beside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          FavouritesStrip(
            favourites: [_favourite()],
            drinks: _menu.drinks,
            onReplay: (_) {},
            onDelete: (_) {},
          ),
        ),
      );

      final photo = tester.getRect(_photo);
      final name = tester.getRect(find.textContaining('قهوة الصبح'));
      expect(photo.bottom, lessThanOrEqualTo(name.top));
    });

    testWidgets('an unavailable one keeps its warning mark, not a photo', (
      tester,
    ) async {
      final favourite = _favourite(drink: 99);
      await tester.pumpWidget(
        _app(
          FavouriteCard(
            favourite: favourite,
            drink: FavouriteCard.drinkOf(favourite, _menu.drinks),
            available: false,
            fullWidth: true,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });
}
