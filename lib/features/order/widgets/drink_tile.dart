import 'package:flutter/material.dart';

import '../../../data/api/api_config.dart';
import '../../../data/models/catalogue_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';
import '../../../theme/motion.dart';
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
    // Item names are admin-entered in both languages, but nameEn is often
    // empty — localisedName falls back to Arabic rather than showing a blank.
    final name = item.localisedName(
      Localizations.localeOf(context).languageCode,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Dimens.radius),
        // Motion.of collapses this to zero when the platform asks for reduced
        // motion. The colour change still happens either way — only the
        // animation between states stops (§2.3).
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.fast),
          curve: Motion.easeSoft,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Dimens.space2,
            vertical: Dimens.space3,
          ),
          decoration: BoxDecoration(
            color: BrandColors.surface,
            border: Border.all(
              // Selection is marked in BRAND, never in accent. Violet means
              // "from my own jar" and nothing else (rule 3) — reusing it here
              // would make the tile's own violet servings label ambiguous, on
              // the very tile where ownership matters most.
              color: selected ? BrandColors.brand : BrandColors.brandLight,
              width: selected ? Dimens.borderSelected : Dimens.borderHairline,
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
                name,
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
