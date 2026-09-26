import 'package:flutter/material.dart';

import '../../../data/models/catalogue_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';
import 'item_image.dart';

/// One drink in Home's menu: the design's "Recommended" row — picture at the
/// start, name beside it, the state of its stock beneath.
///
/// A row stands for one jar. An owned drink appears twice on Home, once under
/// «من موادي» ([fromOwn]) and once under «من البوفيه», and the row tapped is
/// the one ordered from — the same rule as the composer's tiles.
///
/// **Out of stock is a warning, never a block.** A buffet drink that reads as
/// empty carries a badge and still taps: recorded and physical stock drift,
/// and the order is what should fail, if anything does.
class MenuItemRow extends StatelessWidget {
  const MenuItemRow({
    required this.drink,
    required this.fromOwn,
    required this.onTap,
    super.key,
  });

  final CatalogueItemDto drink;
  final bool fromOwn;
  final VoidCallback onTap;

  static const _imageSize = Dimens.imageMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final name = drink.localisedName(
      Localizations.localeOf(context).languageCode,
    );
    final ownOut = drink.ownServingsLeft <= 0;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsetsDirectional.all(Dimens.space3),
      child: Row(
        children: [
          ItemImage(
            imageUrl: drink.imageUrl,
            category: drink.category,
            size: _imageSize,
          ),
          const SizedBox(width: Dimens.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: text.titleMedium?.copyWith(
                    color: BrandColors.brandSecondary,
                  ),
                ),
                if (fromOwn) ...[
                  const SizedBox(height: Dimens.space1),
                  // Violet: this row is the user's own jar. A depleted jar
                  // reads as a warning, not "unavailable" — it still orders.
                  Text(
                    l10n.servingsLeft(drink.ownServingsLeft),
                    style: text.labelSmall?.copyWith(
                      color: ownOut ? BrandColors.warning : BrandColors.accent,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ] else if (!drink.inStock) ...[
                  const SizedBox(height: Dimens.space2),
                  _OutOfStockBadge(label: l10n.outOfStockBadge),
                ],
              ],
            ),
          ),
          const SizedBox(width: Dimens.space2),
          const Icon(Icons.chevron_right, color: BrandColors.brand),
        ],
      ),
    );
  }
}

/// The design's grey "OUT OF STOCK" pill, in the warning colours: the grey
/// measured 2.43:1, and running out is a warning anyway. Worded as "out at
/// the buffet" because the user's own jar may still have some.
class _OutOfStockBadge extends StatelessWidget {
  const _OutOfStockBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: BrandColors.warningSurface,
      border: Border.all(color: BrandColors.warning),
      borderRadius: BorderRadius.circular(Dimens.radiusSm),
    ),
    child: Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Dimens.space2,
        vertical: Dimens.space1 / 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: Dimens.iconMicro,
            color: BrandColors.warning,
          ),
          const SizedBox(width: Dimens.space1),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: BrandColors.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
