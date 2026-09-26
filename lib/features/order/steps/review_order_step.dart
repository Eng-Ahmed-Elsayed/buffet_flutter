import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalogue_models.dart';
import '../../../data/models/favourite_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/banners.dart';
import '../../../shared/widgets/field_label.dart';
import '../../../shared/widgets/quantity_stepper.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';
import '../composer_controller.dart';
import '../order_mode.dart';
import '../widgets/item_image.dart';
import 'step_footer.dart';

/// The last step: the whole order, checked before it is placed — the design's
/// "Review Order", without its price, payment and promo rows (there is no money
/// in this system).
///
/// Lines the user added, plus the drink still being composed (the draft, at
/// its quantity); where to bring it; notes; save as a favourite; Place order.
/// Identical cups are shown once with ×N — for display only: on the wire they
/// stay identical lines.
class ReviewOrderStep extends ConsumerWidget {
  const ReviewOrderStep({
    required this.catalogue,
    required this.composer,
    required this.mode,
    required this.placing,
    required this.favourites,
    required this.favouritesFull,
    required this.maxFavourites,
    required this.locationController,
    required this.notesController,
    required this.favouriteNameController,
    required this.onEditDraft,
    required this.onClearDraft,
    required this.onChooseDrink,
    required this.onAddAnother,
    required this.onPlaceOrder,
    this.header,
    super.key,
  });

  final CatalogueResponse catalogue;
  final ComposerState composer;
  final OrderMode mode;
  final bool placing;
  final List<FavouriteDto> favourites;
  final bool favouritesFull;
  final int maxFavourites;
  final TextEditingController locationController;
  final TextEditingController notesController;
  final TextEditingController favouriteNameController;
  final VoidCallback onEditDraft;
  final VoidCallback onClearDraft;
  final VoidCallback onChooseDrink;
  final VoidCallback onAddAnother;
  final Future<void> Function() onPlaceOrder;

  /// Shown first, inside the scroll view. Null for none.
  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(composerControllerProvider.notifier);
    final groups = _groups(composer);

    // Room for another drink once the draft (at its quantity) is counted in.
    final linesAfterDraft =
        composer.lines.length +
        (composer.drink == null ? 0 : composer.draftQuantity);
    final roomForAnother = linesAfterDraft < composer.maxLines;

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
                // Notices from the composer (a favourite not replayed in full, a failed
                // placement), inside the scroll view so they never squeeze the step.
                if (header case final Widget header) ...[
                  header,
                  const SizedBox(height: Dimens.space4),
                ],
                // The guest was named on the first step, so here it is a
                // statement — the name has one field, not two.
                if (mode == OrderMode.guest &&
                    (composer.onBehalfOfName ?? '').isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        color: BrandColors.iconBlue,
                      ),
                      const SizedBox(width: Dimens.space2),
                      Expanded(
                        child: Text(
                          l10n.orderingFor(composer.onBehalfOfName!),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Dimens.space4),
                ],

                // Nothing left to order: say so, and offer the way back, so
                // the disabled Place order below is never unexplained.
                if (groups.isEmpty) ...[
                  EmptyState(
                    icon: Icons.local_cafe_outlined,
                    title: l10n.reviewEmptyTitle,
                    body: l10n.reviewEmptyBody,
                    action: FilledButton.tonal(
                      onPressed: onChooseDrink,
                      child: Text(l10n.chooseADrink),
                    ),
                  ),
                  const SizedBox(height: Dimens.space3),
                ],

                for (final group in groups) ...[
                  _LineCard(
                    group: group,
                    extras: catalogue.extras,
                    onRemove: () {
                      if (group.isDraft) {
                        onClearDraft();
                        return;
                      }
                      // Highest index first, so the ones still to remove keep
                      // their positions.
                      for (final i in group.indices.reversed) {
                        controller.removeLine(i);
                      }
                    },
                    // One fewer cup of a group of added lines.
                    onRemoveOne: !group.isDraft && group.count > 1
                        ? () => controller.removeLine(group.indices.last)
                        : null,
                    onEdit: group.isDraft ? onEditDraft : null,
                    // The drink still being composed keeps its full stepper,
                    // within the same structural limits as on its own step.
                    quantity: group.isDraft && composer.offersQuantity
                        ? QuantityStepper(
                            valueLabel: l10n.quantity,
                            value: composer.draftQuantity,
                            max: composer.maxDraftQuantity,
                            onChanged: controller.setDraftQuantity,
                            moreTooltip: l10n.quantityMore,
                            fewerTooltip: l10n.quantityFewer,
                            atMaxReason: l10n.quantityAtMost(
                              composer.maxDraftQuantity,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: Dimens.space3),
                ],

                // The caps, explained where the user can act on them. They
                // never disable Place order: the user fixes the buffet cap by
                // switching a drink to their own jar or removing one.
                if (composer.exceedsBuffetCap ||
                    composer.draftWouldExceedBuffetCap) ...[
                  InlineBanner(
                    tone: BannerTone.warning,
                    title: l10n.buffetCapTitle(composer.maxBuffetDrinks),
                    body: l10n.buffetCapBody,
                  ),
                  const SizedBox(height: Dimens.space3),
                ],
                if (!roomForAnother) ...[
                  InlineBanner(
                    tone: BannerTone.warning,
                    title: l10n.maxLinesReachedTitle,
                    body: l10n.maxLinesReachedBody(composer.maxLines),
                  ),
                  const SizedBox(height: Dimens.space3),
                ] else
                  OutlinedButton.icon(
                    onPressed: onAddAnother,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addAnotherDrink),
                  ),
                const SizedBox(height: Dimens.space5),

                // Plain text, deliberately — no suggestion list. Free text
                // always sends `locationText`, which the server accepts for
                // any place at all, so an unlisted spot never blocks an order.
                MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FieldLabel(label: l10n.deliveryLocation),
                      TextField(
                        controller: locationController,
                        decoration: InputDecoration(
                          hintText: l10n.locationHint,
                          prefixIcon: const Icon(Icons.place_outlined),
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (text) =>
                            controller.setLocation(locationText: text),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Dimens.space4),
                MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FieldLabel(label: l10n.orderNotes),
                      TextField(
                        controller: notesController,
                        decoration: InputDecoration(
                          hintText: l10n.orderNotesHint,
                          prefixIcon: const Icon(Icons.notes_outlined),
                        ),
                        minLines: 2,
                        maxLines: 4,
                        textInputAction: TextInputAction.done,
                        onChanged: (text) => controller.setNotes(
                          text.trim().isEmpty ? null : text.trim(),
                        ),
                      ),
                    ],
                  ),
                ),

                // Never in guest mode: a visitor's order is not the user's
                // habit, and the server drops the guest from a favourite.
                if (composer.allLines.isNotEmpty && mode == OrderMode.self) ...[
                  const SizedBox(height: Dimens.space5),
                  SaveFavouriteControl(
                    composer: composer,
                    full: favouritesFull,
                    maxFavourites: maxFavourites,
                    nameController: favouriteNameController,
                    // Replaying a favourite and saving it again would write a
                    // second identical copy — the server does not dedupe.
                    alreadySaved: favourites.any(
                      (f) => f.orders([
                        for (final line in composer.allLines) line.toDto(),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        StepFooter(
          child: FilledButton(
            // Disabled only when there is nothing to order, or while the
            // request is in flight (the spinner says so). NEVER on a stock
            // reading, and never on a missing guest name — the handler takes
            // the user back to the field and shows the error there.
            onPressed: composer.allLines.isNotEmpty && !placing
                ? () => onPlaceOrder()
                : null,
            child: placing
                ? const SizedBox(
                    width: Dimens.space5,
                    height: Dimens.space5,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: BrandColors.surface,
                    ),
                  )
                : Text(l10n.placeOrder),
          ),
        ),
      ],
    );
  }
}

/// Identical cups, shown once.
class _Group {
  _Group({
    required this.line,
    required this.indices,
    required this.isDraft,
    int? count,
  }) : count = count ?? indices.length;

  final ComposerLine line;

  /// Positions in [ComposerState.lines]; empty for the draft.
  final List<int> indices;
  final bool isDraft;
  final int count;
}

String _key(ComposerLine l) => [
  l.drink.itemId,
  l.variantId,
  l.sugarItemId,
  l.sugarSpoons,
  (l.extraItemIds.toList()..sort()).join(','),
  l.drinkFromOwn,
  l.sugarFromOwn,
  (l.ownExtraItemIds.toList()..sort()).join(','),
].join('|');

List<_Group> _groups(ComposerState composer) {
  final byKey = <String, List<int>>{};
  for (final (i, line) in composer.lines.indexed) {
    byKey.putIfAbsent(_key(line), () => []).add(i);
  }
  return [
    for (final indices in byKey.values)
      _Group(
        line: composer.lines[indices.first],
        indices: indices,
        isDraft: false,
      ),
    if (composer.draftLine case final ComposerLine draft)
      _Group(
        line: draft,
        indices: const [],
        isDraft: true,
        count: composer.draftQuantity,
      ),
  ];
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.group,
    required this.extras,
    required this.onRemove,
    required this.onRemoveOne,
    required this.onEdit,
    required this.quantity,
  });

  final _Group group;
  final List<CatalogueItemDto> extras;
  final VoidCallback onRemove;

  /// Drops one cup of a group of added lines; null when there is only one.
  final VoidCallback? onRemoveOne;

  /// The draft's stepper, when it offers one; shown under the line.
  final Widget? quantity;

  /// Only the draft can be reopened; added lines can be removed.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final language = Localizations.localeOf(context).languageCode;
    final line = group.line;

    // "Preparation · N spoons · extras", as the design's tracking lines read.
    final variant = line.drink.variants
        .where((v) => v.variantId == line.variantId)
        .firstOrNull;
    final extraNames = [
      for (final e in extras)
        if (line.extraItemIds.contains(e.itemId)) e.localisedName(language),
    ];
    final summary = [
      if (variant != null && line.drink.variants.length > 1)
        variant.localisedName(language),
      l10n.spoons(line.sugarSpoons),
      if (extraNames.isNotEmpty)
        extraNames.join(language == 'ar' ? '، ' : ', '),
    ].join(' · ');

    return AppCard(
      onTap: onEdit,
      semanticLabel: onEdit == null ? null : l10n.editDrink,
      padding: const EdgeInsetsDirectional.all(Dimens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ItemImage(
                imageUrl: line.drink.imageUrl,
                category: line.drink.category,
                size: 56,
              ),
              const SizedBox(width: Dimens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.drink.localisedName(language),
                      style: text.titleMedium?.copyWith(
                        color: BrandColors.brandSecondary,
                      ),
                    ),
                    Text(summary, style: text.bodySmall),
                    // Violet only when the cup really comes from the user's own
                    // jar; one that falls back to the buffet is not "mine".
                    if (!line.resolvesToBuffet)
                      Text(
                        l10n.sectionMyMaterials,
                        style: text.labelSmall?.copyWith(
                          color: BrandColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    // The shortage is shown, never used to block or remove.
                    if (line.ownStockIsShort)
                      Text(
                        l10n.ownStockShortTitle,
                        style: text.labelSmall?.copyWith(
                          color: BrandColors.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              if (onRemoveOne != null)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: l10n.removeOneCup,
                  onPressed: onRemoveOne,
                ),
              if (group.count > 1 && quantity == null)
                Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: Dimens.space2,
                  ),
                  child: Text(
                    '×${group.count}',
                    style: text.titleMedium
                        ?.merge(AppTheme.tabularFigures)
                        .copyWith(color: BrandColors.brandSecondary),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.removeDrink,
                onPressed: onRemove,
              ),
            ],
          ),
          if (quantity != null) ...[
            const SizedBox(height: Dimens.space2),
            quantity!,
          ],
        ],
      ),
    );
  }
}

/// The "save this for next time" toggle, with its optional name.
///
/// **The cap is the one limit this app does disable a control on.** It is
/// structural — the server refuses past it — not a stock reading, and the
/// disabled switch is never a dead end: the banner beside it says what the
/// limit is and that deleting one makes room.
class SaveFavouriteControl extends ConsumerWidget {
  const SaveFavouriteControl({
    required this.composer,
    required this.full,
    required this.maxFavourites,
    required this.nameController,
    this.alreadySaved = false,
    super.key,
  });

  final ComposerState composer;
  final bool full;
  final int maxFavourites;
  final TextEditingController nameController;

  /// Whether what is on screen is already in the user's favourites.
  final bool alreadySaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(composerControllerProvider.notifier);

    // The field is the only visible part of the name, so it must agree with
    // the state: switching the toggle off drops the name, and a field still
    // showing one would name the next saved favourite after this order.
    final name = composer.favouriteName ?? '';
    if (nameController.text.trim() != name) {
      nameController.value = TextEditingValue(
        text: name,
        selection: TextSelection.collapsed(offset: name.length),
      );
    }

    // Said plainly and the control withdrawn, rather than a toggle that would
    // silently write a duplicate. Matches the order-history row exactly.
    if (alreadySaved) {
      return Row(
        children: [
          const Icon(Icons.star, size: 16, color: BrandColors.brand),
          const SizedBox(width: Dimens.space2),
          Flexible(
            child: Text(
              l10n.favouriteAlreadySaved,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: BrandColors.muted),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (full) ...[
          InlineBanner(
            tone: BannerTone.warning,
            title: l10n.favouritesFullTitle,
            body: l10n.favouritesFullBody(maxFavourites),
          ),
          const SizedBox(height: Dimens.space3),
        ],
        SwitchListTile.adaptive(
          value: composer.saveAsFavourite,
          // Disabled only at the cap, and only with the banner above saying
          // so. Never on a stock reading.
          onChanged: full ? null : controller.setSaveAsFavourite,
          title: Text(l10n.saveAsFavourite),
          contentPadding: EdgeInsetsDirectional.zero,
          activeThumbColor: BrandColors.brand,
        ),
        // The name is genuinely optional — blank means "name it after the
        // drinks" — so the field appears only once saving is asked for.
        if (composer.saveAsFavourite) ...[
          const SizedBox(height: Dimens.space2),
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: l10n.favouriteNameLabel,
              hintText: l10n.favouriteNameHint,
              prefixIcon: const Icon(Icons.star_outline),
            ),
            textInputAction: TextInputAction.done,
            onChanged: controller.setFavouriteName,
          ),
        ],
      ],
    );
  }
}
