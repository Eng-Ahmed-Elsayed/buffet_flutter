import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalogue_models.dart';
import '../composer_screen.dart';
import 'item_image.dart';

/// A drink's photograph where only its id is at hand: an order line, a
/// favourite. Orders and favourites carry `drinkItemId` but no picture, so the
/// picture comes from the catalogue, which the screen showing them already
/// loads to name the drinks.
///
/// Decorative, like every [ItemImage]: the name beside it says what it is.
/// While the menu loads it holds a neutral frame rather than the glyph, which
/// would claim the drink has no picture. A drink since retired from the menu
/// gets the glyph.
class DrinkPhoto extends ConsumerWidget {
  const DrinkPhoto({required this.drinkItemId, required this.size, super.key});

  final int drinkItemId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(catalogueProvider);
    if (catalogue.isLoading && !catalogue.hasValue) {
      return ItemImage.placeholder(size);
    }
    for (final drink
        in catalogue.valueOrNull?.drinks ?? const <CatalogueItemDto>[]) {
      if (drink.itemId == drinkItemId) {
        return ItemImage(
          imageUrl: drink.imageUrl,
          category: drink.category,
          size: size,
        );
      }
    }
    return ItemImage(imageUrl: null, category: '', size: size);
  }
}
