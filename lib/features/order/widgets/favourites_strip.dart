import 'package:flutter/material.dart';

import '../../../data/models/favourite_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';

/// The one-tap repeat: the caller's saved orders, replayed by tapping one.
///
/// This is what replaced the catalogue's "usual order" card, and the difference
/// is the whole point — that one was the last order, guessed and silently
/// moving; these are the ones the user said were worth keeping. Keeping both
/// side by side is what the removal was for, so **do not reintroduce a
/// last-order card next to this** (§7.6).
///
/// Tapping seeds the composer rather than placing outright: the user still sees
/// and confirms the drink, and a favourite holding an item retired since it was
/// saved shows up as something they can look at rather than a rejection they
/// cannot act on.
class FavouritesStrip extends StatelessWidget {
  const FavouritesStrip({
    required this.favourites,
    required this.onReplay,
    required this.onDelete,
    this.availableItemIds,
    this.maxVisible = 4,
    this.onShowAll,
    super.key,
  });

  final List<FavouriteDto> favourites;
  final void Function(FavouriteDto favourite) onReplay;
  final void Function(FavouriteDto favourite) onDelete;

  /// What the catalogue currently carries, used to mark a favourite whose
  /// drink an admin has since disabled or removed.
  ///
  /// Null while the catalogue has not loaded — everything renders as available
  /// rather than the strip flashing "unavailable" over a list that is merely
  /// waiting on a request.
  final Set<int>? availableItemIds;

  /// How many cards the strip shows before deferring the rest to [onShowAll].
  ///
  /// The cap is **20 per user**, and twenty cards stacked on the hub would push
  /// "New order" clean off a phone screen — this screen is for ordering a
  /// drink, not for managing a list. Four is about one screenful of thumb
  /// reach, and the rest are one tap away.
  final int maxVisible;

  /// Opens the full list. Null hides the link even when there are more, for a
  /// caller with nowhere to send the user.
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Most recently USED first, falling back to newest saved for one never
    // ordered. `lastUsedAtUtc` exists precisely so a client can lead with what
    // is actually in use rather than what was saved longest ago — and it is
    // what makes truncating to [maxVisible] honest, since the ones cut are the
    // ones least likely to be wanted.
    final ordered = [...favourites]
      ..sort((a, b) {
        final left = a.lastUsedAtUtc ?? a.createdAtUtc;
        final right = b.lastUsedAtUtc ?? b.createdAtUtc;
        return right.compareTo(left);
      });

    // Truncate ONLY when there is somewhere to send the user for the rest.
    // Hiding a favourite behind a link that is not there would lose it exactly
    // as silently as filtering a retired one out — the thing this whole
    // feature refuses to do.
    final canDefer = onShowAll != null;
    final hidden = canDefer ? ordered.length - maxVisible : 0;
    final visible = hidden > 0 ? ordered.take(maxVisible).toList() : ordered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.star_outline, size: 18, color: BrandColors.brand),
            const SizedBox(width: Dimens.space2),
            // Expanded so the heading wraps rather than pushing itself off the
            // edge at a large text scale on a narrow phone.
            Expanded(
              child: Text(
                l10n.favourites,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: Dimens.space3),
        // A Wrap, not a horizontal ListView: a row that scrolls sideways hides
        // its own contents, and at a large text scale one card can be wider
        // than the screen. These grow downwards instead.
        //
        // Two per row, sized from the measured width rather than capped at a
        // fixed maximum. A fixed 220dp cap put ONE card per row on a 320dp
        // phone, so four favourites became four full-height rows and pushed
        // "New order" — the primary action of the whole app — off the first
        // screen entirely. Measured columns halve that, and the tiles still
        // grow taller with the text scale rather than clipping.
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - Dimens.space3) / 2;
            return Wrap(
              spacing: Dimens.space3,
              runSpacing: Dimens.space3,
              children: [
                for (final favourite in visible)
                  FavouriteCard(
                    favourite: favourite,
                    width: tileWidth,
                    // Null means "not known yet", which renders as available.
                    available:
                        availableItemIds == null ||
                        favourite.isAvailable(availableItemIds!),
                    onTap: () => onReplay(favourite),
                    onLongPress: () => onDelete(favourite),
                  ),
              ],
            );
          },
        ),
        // Only when there is genuinely more to see. The count is on the label
        // so the user knows whether it is worth the tap.
        if (hidden > 0) ...[
          const SizedBox(height: Dimens.space2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: onShowAll,
              child: Text(l10n.favouritesShowAll(favourites.length)),
            ),
          ),
        ],
      ],
    );
  }
}

/// One saved order.
///
/// Shared by the strip and the full favourites screen so the two can never
/// disagree about what a favourite looks like or how it behaves.
class FavouriteCard extends StatelessWidget {
  const FavouriteCard({
    required this.favourite,
    required this.onTap,
    required this.onLongPress,
    this.available = true,
    this.fullWidth = false,
    this.width,
    super.key,
  });

  final FavouriteDto favourite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Whether every item this favourite names is still in the catalogue.
  ///
  /// **False still renders, and still taps.** The server deliberately does not
  /// filter these out (§7.6): a favourite that silently vanished would leave
  /// the user with nothing to act on and no way to delete what they cannot
  /// see. Marked and explained is the honest version — and tapping still seeds
  /// the composer, where the missing drink is a line they can look at.
  final bool available;

  /// Lets the full-screen list use the same card at row width.
  final bool fullWidth;

  /// The measured column width from the strip. Null on the full-width list.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Server-composed from mixed script — an item name plus an Arabic
    // parenthetical — so it is isolated whichever way the page runs (§2.4).
    final name = Formatters.isolate(favourite.name);

    final card = Semantics(
      button: true,
      label: available
          ? favourite.name
          : '${favourite.name}، ${l10n.favouriteUnavailable}',
      // Long-press is the delete affordance, so it must be announced —
      // otherwise the only way to remove a favourite is invisible to a
      // screen reader.
      onLongPressHint: l10n.favouriteDelete,
      // AppCard's own onTap has no long-press, and the delete affordance
      // needs one — so the gesture is taken here and the card is left
      // presentational. Ink is clipped to the same radius the card draws.
      child: Material(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(Dimens.radiusLg),
          child: AppCard(
            // Warning, never danger: an unavailable favourite is not an error
            // the user made, and it is still a perfectly good thing to tap.
            tone: available ? CardTone.neutral : CardTone.warning,
            padding: const EdgeInsetsDirectional.all(Dimens.space3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    Icon(
                      available ? Icons.replay : Icons.error_outline,
                      size: 16,
                      color: available
                          ? BrandColors.brand
                          : BrandColors.warning,
                    ),
                    const SizedBox(width: Dimens.space2),
                    Flexible(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.bodyMedium,
                        // Two lines in the strip, where vertical space is what
                        // stands between the user and the order button; the
                        // full list has room for three.
                        maxLines: fullWidth ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // A VISIBLE delete on the full list, which is the screen
                    // whose whole job is managing these. Long-press alone is
                    // undiscoverable — nobody long-presses to find out what
                    // happens — and it is the only way to clear the cap that
                    // disables the save control elsewhere. The compact strip
                    // keeps long-press only, because a second target per tile
                    // there would not survive a 320dp phone.
                    if (fullWidth)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: l10n.favouriteDelete,
                        onPressed: onLongPress,
                      ),
                  ],
                ),
                // Said in words, not by colour alone (§2.5) — and it says what
                // to do about it, so the mark is never a dead end.
                if (!available) ...[
                  const SizedBox(height: Dimens.space2),
                  Text(
                    l10n.favouriteUnavailable,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: BrandColors.warning),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return fullWidth ? card : SizedBox(width: width, child: card);
  }
}
