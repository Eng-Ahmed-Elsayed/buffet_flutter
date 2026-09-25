import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalogue_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/banners.dart';
import '../../../shared/widgets/quantity_stepper.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';
import '../../../theme/motion.dart';
import '../composer_controller.dart';
import '../widgets/item_image.dart';
import '../widgets/sugar_stepper.dart';
import 'step_footer.dart';

/// The second step: one drink, made the way the user wants it — the design's
/// Drink Details.
///
/// Its hero picture and title, then only the choices this drink really
/// offers: which jar (only when the user owns some), the preparation (only
/// when there is more than one), sugar, the extras it permits, and how many
/// cups (only when the order may structurally hold more than one).
class DrinkDetailsStep extends ConsumerWidget {
  const DrinkDetailsStep({
    required this.catalogue,
    required this.composer,
    required this.onContinue,
    super.key,
  });

  final CatalogueResponse catalogue;
  final ComposerState composer;
  final VoidCallback onContinue;

  static const _heroSize = 160.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final controller = ref.read(composerControllerProvider.notifier);
    final drink = composer.drink;
    final language = Localizations.localeOf(context).languageCode;

    // Seeded a frame after the step opens; nothing to show until then.
    if (drink == null) return const SizedBox.shrink();

    final extras = _visibleExtras(catalogue.extras, drink);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Dimens.gutter,
              vertical: Dimens.space5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ItemImage(
                    imageUrl: drink.imageUrl,
                    category: drink.category,
                    size: _heroSize,
                  ),
                ),
                const SizedBox(height: Dimens.space5),
                AppCard(
                  padding: const EdgeInsetsDirectional.all(Dimens.space5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        drink.localisedName(language),
                        style: text.headlineMedium,
                      ),

                      // Which jar: only for a drink the user owns any of.
                      // Violet for their own jar, brand for the buffet — never
                      // violet for a generic selection (rule 3).
                      if (drink.hasOwnStock) ...[
                        const SizedBox(height: Dimens.space5),
                        _Label(l10n.drinkSource),
                        Wrap(
                          spacing: Dimens.space2,
                          runSpacing: Dimens.space2,
                          children: [
                            _SourceChip(
                              label: l10n.sectionMyMaterials,
                              selected: composer.drinkFromOwn,
                              own: true,
                              onSelected: () => controller
                                ..setDrinkFromOwn(true)
                                ..setDraftQuantity(composer.draftQuantity),
                            ),
                            _SourceChip(
                              label: l10n.sectionBuffet,
                              selected: !composer.drinkFromOwn,
                              own: false,
                              // The buffet may allow fewer cups than the jar
                              // did, so the count is re-clamped on the switch.
                              onSelected: () => controller
                                ..setDrinkFromOwn(false)
                                ..setDraftQuantity(composer.draftQuantity),
                            ),
                          ],
                        ),
                      ],

                      // Warns, never blocks: stock readings drift, and the
                      // order still goes through (rule 2).
                      AnimatedSwitcher(
                        duration: Motion.of(context, Motion.base),
                        switchInCurve: Motion.easeOut,
                        switchOutCurve: Motion.easeSoft,
                        child: composer.ownStockIsShort
                            ? Padding(
                                key: const ValueKey('own-stock-short'),
                                padding: const EdgeInsetsDirectional.only(
                                  top: Dimens.space4,
                                ),
                                child: InlineBanner(
                                  tone: BannerTone.warning,
                                  title: l10n.ownStockShortTitle,
                                  body: l10n.ownStockShortBody,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      // Only when this drink is made more than one way — the
                      // design's "choose size" row, holding what the business
                      // really varies.
                      if (drink.variants.length > 1) ...[
                        const SizedBox(height: Dimens.space5),
                        _Label(l10n.preparation),
                        Wrap(
                          spacing: Dimens.space2,
                          runSpacing: Dimens.space2,
                          children: [
                            for (final variant in drink.variants)
                              ChoiceChip(
                                label: Text(variant.localisedName(language)),
                                selected:
                                    composer.variantId == variant.variantId,
                                onSelected: (_) =>
                                    controller.selectVariant(variant.variantId),
                                // Brand, not accent: a preparation choice is
                                // not a statement about whose jar it is.
                                selectedColor: BrandColors.brandLight,
                                // The theme's selected label and checkmark are
                                // white, for its bright fill; on this pale fill
                                // white would vanish, so both are set here.
                                labelStyle: Theme.of(context)
                                    .chipTheme
                                    .labelStyle
                                    ?.copyWith(color: BrandColors.ink),
                                checkmarkColor: BrandColors.brand,
                              ),
                          ],
                        ),
                      ],

                      const SizedBox(height: Dimens.space5),
                      _Label(l10n.sugar),
                      SugarStepper(
                        spoons: composer.sugarSpoons,
                        onChanged: controller.setSugarSpoons,
                      ),

                      // Filtered by the drink: null permits every extra, an
                      // empty list hides the row. Not cosmetic — an extra the
                      // drink does not permit is dropped server-side while the
                      // order still succeeds.
                      if (extras.isNotEmpty) ...[
                        const SizedBox(height: Dimens.space5),
                        _Label(l10n.extras),
                        Wrap(
                          spacing: Dimens.space2,
                          runSpacing: Dimens.space2,
                          children: [
                            for (final extra in extras)
                              _ExtraChip(
                                extra: extra,
                                selected: composer.extraItemIds.contains(
                                  extra.itemId,
                                ),
                                fromOwn: composer.ownExtraItemIds.contains(
                                  extra.itemId,
                                ),
                                // Follows the PREPARATION, not the drink.
                                doublesUp: composer.extraDoublesUp(
                                  extra.itemId,
                                ),
                                // An extra the user owns and has servings of
                                // comes from their jar unless they switch it
                                // below. One with none left defaults to the
                                // buffet rather than into a known shortage,
                                // and can still be switched, never blocked.
                                onTap: () => controller.toggleExtra(
                                  extra.itemId,
                                  fromOwn:
                                      extra.hasOwnStock &&
                                      extra.ownServingsLeft > 0,
                                ),
                              ),
                          ],
                        ),
                        // The jar for each ticked extra the user owns, said
                        // and chosen the same way as the drink's above. This is
                        // what decides `ownExtraItemIds`; the chip's violet
                        // only reports it.
                        for (final extra in extras)
                          if (extra.hasOwnStock &&
                              composer.extraItemIds.contains(extra.itemId)) ...[
                            const SizedBox(height: Dimens.space3),
                            _Label(extra.localisedName(language)),
                            Wrap(
                              spacing: Dimens.space2,
                              runSpacing: Dimens.space2,
                              children: [
                                _SourceChip(
                                  label: l10n.sectionMyMaterials,
                                  selected: composer.ownExtraItemIds.contains(
                                    extra.itemId,
                                  ),
                                  own: true,
                                  onSelected: () => controller.setExtraFromOwn(
                                    extra.itemId,
                                    true,
                                  ),
                                ),
                                _SourceChip(
                                  label: l10n.sectionBuffet,
                                  selected: !composer.ownExtraItemIds.contains(
                                    extra.itemId,
                                  ),
                                  own: false,
                                  onSelected: () => controller.setExtraFromOwn(
                                    extra.itemId,
                                    false,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        // A warning, never a block: a double portion is a
                        // legitimate thing to order.
                        if (composer.doubledExtraItemIds.isNotEmpty) ...[
                          const SizedBox(height: Dimens.space3),
                          InlineBanner(
                            tone: BannerTone.warning,
                            title: l10n.extraDoublesHint,
                          ),
                        ],
                      ],

                      // Only when the order may hold more than one of this
                      // drink, from structural limits alone (never stock).
                      if (composer.offersQuantity) ...[
                        const SizedBox(height: Dimens.space5),
                        _Label(l10n.quantity),
                        QuantityStepper(
                          value: composer.draftQuantity,
                          max: composer.maxDraftQuantity,
                          onChanged: controller.setDraftQuantity,
                          moreTooltip: l10n.quantityMore,
                          fewerTooltip: l10n.quantityFewer,
                          atMaxReason: l10n.quantityAtMost(
                            composer.maxDraftQuantity,
                          ),
                        ),
                      ],

                      // The buffet cap, explained where the user can act on it
                      // — by switching this drink to their own jar or choosing
                      // fewer cups — rather than as a 400 after the fact.
                      if (composer.draftWouldExceedBuffetCap ||
                          composer.exceedsBuffetCap) ...[
                        const SizedBox(height: Dimens.space4),
                        InlineBanner(
                          tone: BannerTone.warning,
                          title: l10n.buffetCapTitle,
                          body: l10n.buffetCapBody,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        StepFooter(
          child: FilledButton(
            onPressed: onContinue,
            child: Text(l10n.continueToReview),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: Dimens.space2),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

/// Which jar this cup comes from. The own-jar choice is violet — its whole
/// meaning is "from my own jar" — and the buffet choice is brand.
class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.selected,
    required this.own,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final bool own;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
    selectedColor: own ? BrandColors.accentSurface : BrandColors.brandLight,
    checkmarkColor: own ? BrandColors.accent : BrandColors.brand,
    // Pale fills, so the label stays ink rather than the theme's white.
    labelStyle: Theme.of(context).chipTheme.labelStyle
        ?.copyWith(color: BrandColors.ink),
    side: WidgetStateBorderSide.resolveWith(
      (states) => BorderSide(
        color: !states.contains(WidgetState.selected)
            ? BrandColors.outline
            : (own ? BrandColors.accent : BrandColors.brand),
      ),
    ),
  );
}

/// The extras this drink permits, in catalogue order. A null
/// [CatalogueItemDto.allowedExtraItemIds] means unrestricted; an empty list
/// means none, and the caller hides the row.
List<CatalogueItemDto> _visibleExtras(
  List<CatalogueItemDto> extras,
  CatalogueItemDto drink,
) => [
  for (final e in extras)
    if (drink.permitsExtra(e.itemId)) e,
];

/// An extras chip, carrying two independent markings that must not be
/// confused:
///
/// - **Violet** means this extra, ticked, is drawn from the user's own jar
///   ([fromOwn]), not merely that they own some. Never a generic selected
///   state (rule 3).
/// - **A warning mark** means the chosen preparation already pours this, so
///   ticking it is a second portion. It annotates, never filters.
class _ExtraChip extends StatelessWidget {
  const _ExtraChip({
    required this.extra,
    required this.selected,
    required this.fromOwn,
    required this.doublesUp,
    required this.onTap,
  });

  final CatalogueItemDto extra;
  final bool selected;

  /// Whether the order draws this extra from the user's own jar.
  final bool fromOwn;
  final bool doublesUp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = extra.localisedName(
      Localizations.localeOf(context).languageCode,
    );

    return Tooltip(
      message: doublesUp ? l10n.extraAlreadyInPreparation : name,
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name),
            if (doublesUp) ...[
              const SizedBox(width: Dimens.space1),
              const Icon(
                Icons.add_circle_outline,
                size: 14,
                color: BrandColors.warning,
              ),
            ],
          ],
        ),
        selected: selected,
        onSelected: (_) => onTap(),
        // Violet only when the order really draws it from the user's jar. It
        // used to follow ownership alone, and an owned extra went out as buffet
        // stock under a violet chip that said otherwise.
        selectedColor: fromOwn
            ? BrandColors.accentSurface
            : BrandColors.brandLight,
        checkmarkColor: fromOwn ? BrandColors.accent : BrandColors.brand,
        // The theme's white selected label is for its bright-blue fill; on
        // these pale fills it would vanish, so the label stays ink.
        labelStyle: Theme.of(context).chipTheme.labelStyle
            ?.copyWith(color: BrandColors.ink),
        side: fromOwn
            ? WidgetStateBorderSide.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.selected)
                      ? BrandColors.accent
                      : BrandColors.outline,
                ),
              )
            : null,
      ),
    );
  }
}
