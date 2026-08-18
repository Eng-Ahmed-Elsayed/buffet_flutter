import 'package:flutter/material.dart';

import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';

/// An item's photograph, uploaded by an admin and served from `/uploads/items/`.
///
/// Three cases, all normal:
/// - a URL that loads — the real picture;
/// - a null URL — the item has no uploaded image;
/// - a URL that **404s** — the uploads folder is not covered by database
///   backups, so a row can outlive its file (§7.1).
///
/// All three fall through to a category glyph. A broken image is never
/// surfaced as an error, and never blocks anything.
class ItemImage extends StatelessWidget {
  const ItemImage({
    required this.imageUrl,
    required this.category,
    this.size = 40,
    super.key,
  });

  final String? imageUrl;
  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) return _fallback();

    return ClipRRect(
      borderRadius: BorderRadius.circular(Dimens.radiusSm),
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // A 404 or a dead connection is "use the fallback", not an error.
        errorBuilder: (context, error, stackTrace) => _fallback(),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _fallback(),
        // Decoding at display size keeps a long list from holding full-size
        // bitmaps in memory.
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
      ),
    );
  }

  Widget _fallback() => SizedBox(
    width: size,
    height: size,
    child: Icon(
      _glyphFor(category),
      size: size * 0.75,
      color: BrandColors.brand,
    ),
  );

  /// Category names are admin-entered, so this matches loosely on both
  /// languages and falls back to a neutral cup rather than guessing.
  static IconData _glyphFor(String category) {
    final normalised = category.toLowerCase();
    if (normalised.contains('tea') || normalised.contains('شاي')) {
      return Icons.emoji_food_beverage_outlined;
    }
    if (normalised.contains('coffee') || normalised.contains('قهوة')) {
      return Icons.coffee_outlined;
    }
    if (normalised.contains('water') || normalised.contains('مياه')) {
      return Icons.water_drop_outlined;
    }
    if (normalised.contains('juice') || normalised.contains('عصير')) {
      return Icons.local_bar_outlined;
    }
    if (normalised.contains('sugar') || normalised.contains('سكر')) {
      return Icons.grain_outlined;
    }
    return Icons.local_cafe_outlined;
  }
}
