import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/favourite_models.dart';
import '../../data/repositories/favourites_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/error_text.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import 'composer_screen.dart';
import 'favourites_controller.dart';
import 'order_mode.dart';
import 'widgets/favourites_strip.dart';

/// Confirms, then deletes a favourite.
///
/// Shared by every screen that shows a favourite, so the confirmation, the
/// wording and the refresh cannot drift apart between them. A long-press that
/// deleted outright would be destructive with no undo, behind an easily
/// mistaken gesture.
Future<void> confirmDeleteFavourite(
  BuildContext context,
  WidgetRef ref,
  FavouriteDto favourite,
) async {
  final l10n = AppLocalizations.of(context);
  final locale = ref.read(localeControllerProvider);
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.favouriteDelete),
      // Isolated: the name is server-composed mixed script (§2.4).
      content: Text(
        l10n.favouriteDeleteConfirm(Formatters.isolate(favourite.name)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: BrandColors.danger),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref
        .read(favouritesRepositoryProvider)
        .deleteFavourite(
          favouriteId: favourite.favouriteId,
          languageCode: locale.languageCode,
          networkErrorFallback: l10n.networkError,
        );
    ref.invalidate(favouritesProvider);
    messenger.showSnackBar(SnackBar(content: Text(l10n.favouriteDeleted)));
  } on ApiException catch (error) {
    // The server's message, already localised — never a code mapped here (§4).
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
}

/// The full list of saved orders.
///
/// The Favourites tab, and `/favourites-list` from the composer's "show all"
/// (where [returnsPick] hands the choice back). The strips show only the four
/// most recently used; this is where the rest live, and where somebody goes to
/// tidy the list rather than to order.
class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({this.returnsPick = false, super.key});

  /// Opened from inside the composer ("show all"): a tap hands the favourite
  /// back to that composer instead of opening another one on top of it. Two
  /// composers share one state, and stacking them wiped a guest's name,
  /// merged their orders and lost a staff member's served confirmation.
  final bool returnsPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final favourites = ref.watch(favouritesProvider);
    // Null while loading: a favourite renders as available until the catalogue
    // says otherwise, rather than the list flashing "unavailable" over a
    // request that has simply not come back yet.
    final drinks = ref.watch(catalogueProvider).valueOrNull?.drinks;
    final available = drinks?.map((d) => d.itemId).toSet();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.favouritesTitle)),
      body: favourites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.genericError,
          body: describeError(error, l10n),
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(favouritesProvider),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ),
        data: (data) {
          if (data.favourites.isEmpty) {
            // Stacked over an empty ListView so pull-to-refresh still works —
            // an empty list you cannot refresh is a dead end.
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(favouritesProvider),
              child: Stack(
                children: [
                  ListView(),
                  EmptyState(
                    icon: Icons.favorite_border,
                    title: l10n.favouritesEmptyTitle,
                    // Says where a favourite is saved from, and leads there:
                    // an empty tab with no way on was a dead end. Not when
                    // picking for a composer, which is itself the way on.
                    body: l10n.favouritesEmptyHint,
                    action: returnsPick
                        ? null
                        : OutlinedButton(
                            onPressed: () => context.go(Routes.home),
                            child: Text(l10n.orderADrink),
                          ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(favouritesProvider),
            child: ListView(
              padding: const EdgeInsetsDirectional.all(Dimens.space4),
              children: [
                // Stated once at the top rather than repeated on every marked
                // card: it is the same explanation each time, and a warning
                // per row would drown the list it is describing.
                if (available != null &&
                    data.favourites.any((f) => !f.isAvailable(available))) ...[
                  InlineBanner(
                    tone: BannerTone.warning,
                    title: l10n.favouriteUnavailable,
                    body: l10n.favouriteUnavailableBody,
                  ),
                  const SizedBox(height: Dimens.space4),
                ],
                for (final favourite in data.favourites) ...[
                  FavouriteCard(
                    favourite: favourite,
                    fullWidth: true,
                    drink: FavouriteCard.drinkOf(favourite, drinks),
                    available:
                        available == null || favourite.isAvailable(available),
                    // Same as the strip: seeds the composer, never places.
                    onTap: returnsPick
                        ? () => context.pop(favourite)
                        : () => unawaited(
                            context.push(
                              Routes.catalogue,
                              extra: ComposerSeed(
                                mode: OrderMode.self,
                                favourite: favourite,
                              ),
                            ),
                          ),
                    onLongPress: () => unawaited(
                      confirmDeleteFavourite(context, ref, favourite),
                    ),
                  ),
                  const SizedBox(height: Dimens.space3),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
