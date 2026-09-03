import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/locale_controller.dart';
import '../../data/models/favourite_models.dart';
import '../../data/repositories/favourites_repository.dart';

/// The caller's saved orders, with the per-user cap.
///
/// **Deliberately its own provider rather than part of the catalogue.** The
/// catalogue is cached and refreshed on resume, which is right for a list of
/// drinks and wrong for one that changes the moment the user saves a favourite:
/// bundling them would leave a just-saved favourite invisible until the next
/// resume (§7.6).
///
/// Invalidate it after any save or delete — including the save that rides along
/// on `POST /orders`.
final favouritesProvider = FutureProvider.autoDispose<FavouritesResponse>((
  ref,
) async {
  final locale = ref.watch(localeControllerProvider);
  return ref
      .watch(favouritesRepositoryProvider)
      .fetchFavourites(
        languageCode: locale.languageCode,
        // The repository only uses this when there was no response at all.
        networkErrorFallback: 'network',
      );
});
