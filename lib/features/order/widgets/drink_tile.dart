import 'package:flutter/material.dart';

import '../../../data/api/api_config.dart';
import '../../../data/models/catalogue_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';
import 'item_image.dart';

/// A tappable drink tile.
///
/// An item the employee owns is marked in **violet with the servings
/// remaining** — violet means "from my own jar", everywhere.
///
/// The tile is **never disabled on a stock reading**: `inStock == false` is
/// information, not a bar. Halting service is worse than a negative number an
/// admin reconciles later (§7.1).
class DrinkTile extends StatelessWidget {
  const DrinkTile({
    required this.item,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final CatalogueItemDto item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ownStockOut = item.hasOwnStock && item.ownServingsLeft <= 0;

    return Semantics(
      button: true,
      selected: selected,
      label: item.nameAr,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Dimens.radius),
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Dimens.space2,
            vertical: Dimens.space3,
          ),
          decoration: BoxDecoration(
            color: BrandColors.surface,
            border: Border.all(
              color: selected ? BrandColors.accent : BrandColors.brandLight,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(Dimens.radius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ItemImage(
                imageUrl: ApiConfig.imageUrl(item.imageUrl),
                category: item.category,
                size: 40,
              ),
              const SizedBox(height: Dimens.space2),
              Text(
                item.nameAr,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: BrandColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (item.hasOwnStock) ...[
                const SizedBox(height: Dimens.space1),
                Text(
                  l10n.servingsLeft(item.ownServingsLeft),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    // A depleted personal jar reads as a warning, not as
                    // "unavailable" — the order still goes through.
                    color: ownStockOut
                        ? BrandColors.warning
                        : BrandColors.accent,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
