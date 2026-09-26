import 'package:flutter/material.dart';

import '../../../data/models/catalogue_models.dart';
import '../../../data/models/favourite_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/banners.dart';
import '../../../shared/widgets/search_field.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';
import '../composer_controller.dart';
import '../order_mode.dart';
import '../widgets/drink_menu.dart';
import '../widgets/favourites_strip.dart';

/// The first step of ordering: choose a drink.
///
/// Where the flow starts for staff ("order for myself"), for a guest order,
/// and for "add another drink". An employee ordering for themselves skips it
/// — a drink tapped on Home opens the next step directly.
///
/// In guest mode **the guest's name is the first field**, and every way off
/// this step (a drink or a favourite) checks it first: the name is what lifts
/// the buffet cap, so it has to exist before any quantity is offered.
class ChooseDrinkStep extends StatelessWidget {
  const ChooseDrinkStep({
    required this.catalogue,
    required this.composer,
    required this.mode,
    required this.guestNameController,
    required this.guestNameFocusNode,
    required this.guestNameError,
    required this.onGuestNameChanged,
    required this.onGuestNameBlurred,
    required this.favourites,
    required this.onReplayFavourite,
    required this.onDeleteFavourite,
    required this.onShowAllFavourites,
    required this.searchController,
    required this.query,
    required this.onQueryChanged,
    required this.onSelectDrink,
    required this.onReview,
    this.header,
    super.key,
  });

  final CatalogueResponse catalogue;
  final ComposerState composer;
  final OrderMode mode;
  final TextEditingController guestNameController;

  /// Focused, and scrolled to, when a way off this step finds the name
  /// missing: the field is often far above the drink that was tapped.
  final FocusNode guestNameFocusNode;
  final bool guestNameError;
  final ValueChanged<String> onGuestNameChanged;
  final VoidCallback onGuestNameBlurred;
  final List<FavouriteDto> favourites;
  final ValueChanged<FavouriteDto> onReplayFavourite;
  final ValueChanged<FavouriteDto> onDeleteFavourite;

  /// Opens the full list, which hands the chosen favourite back here.
  final VoidCallback onShowAllFavourites;
  final TextEditingController searchController;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final void Function(CatalogueItemDto drink, {required bool fromOwn})
  onSelectDrink;
  final VoidCallback onReview;

  /// Shown first, inside the scroll view. Null for none.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // A Column, not a lazy list: the menu's jump chips scroll to a heading,
    // and a lazy list never builds one that is off screen.
    return SingleChildScrollView(
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
          // Who this is for comes FIRST, and only in guest mode. It changes
          // which rules apply and it is required, so it is asked before the
          // drink rather than discovered after the order is composed.
          if (mode == OrderMode.guest) ...[
            InlineBanner(
              tone: BannerTone.info,
              title: l10n.guestOrderTitle,
              // States the cap-lifting up front, where it explains why this
              // order may take more than one buffet drink.
              body: l10n.guestOrderNote,
            ),
            const SizedBox(height: Dimens.space3),
            Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) onGuestNameBlurred();
              },
              child: TextField(
                controller: guestNameController,
                focusNode: guestNameFocusNode,
                decoration: InputDecoration(
                  labelText: l10n.guestOrderLabel,
                  hintText: l10n.guestOrderHint,
                  prefixIcon: const Icon(Icons.person_outline),
                  errorText: guestNameError ? l10n.guestNameRequired : null,
                ),
                textInputAction: TextInputAction.next,
                onChanged: onGuestNameChanged,
              ),
            ),
            const SizedBox(height: Dimens.space5),
          ],

          // Back here to add another drink: the order so far is one tap away.
          if (composer.lines.isNotEmpty) ...[
            AppCard(
              onTap: onReview,
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    color: BrandColors.iconBlue,
                  ),
                  const SizedBox(width: Dimens.space3),
                  Expanded(
                    child: Text(
                      l10n.drinksInOrder(composer.lines.length),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: BrandColors.brand),
                ],
              ),
            ),
            const SizedBox(height: Dimens.space5),
          ],

          // The strip lives here as well as on Home, and not as a duplicate:
          // staff reach this step from the queue and never see Home, so having
          // it only there would take the one-tap repeat away from them. Shown
          // while composing too: backing out of a drink to pick a favourite
          // instead found the strip gone. A favourite then adds to the order.
          if (favourites.isNotEmpty) ...[
            FavouritesStrip(
              favourites: favourites,
              onReplay: onReplayFavourite,
              onDelete: onDeleteFavourite,
              availableItemIds: {for (final d in catalogue.drinks) d.itemId},
              // No tab bar here, so the full list is a pushed screen — one
              // that returns its pick rather than opening a second composer.
              onShowAll: onShowAllFavourites,
            ),
            const SizedBox(height: Dimens.space5),
          ],

          SearchField(
            controller: searchController,
            hint: l10n.searchDrinksHint,
            clearTooltip: l10n.clearSearch,
            onChanged: onQueryChanged,
          ),
          const SizedBox(height: Dimens.space5),

          DrinkMenu(
            drinks: catalogue.drinks,
            query: query,
            onSelect: onSelectDrink,
          ),
        ],
      ),
    );
  }
}
