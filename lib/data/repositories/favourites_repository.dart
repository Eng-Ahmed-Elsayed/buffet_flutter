import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_exception.dart';
import '../models/catalogue_models.dart';
import '../models/favourite_models.dart';

/// The caller's saved orders — the one-tap repeat that replaced the catalogue's
/// guessed "usual order" (§7.6).
///
/// Caller-scoped like the rest of the employee endpoints: a delete of someone
/// else's favourite is a `404`, never a `403`.
class FavouritesRepository {
  const FavouritesRepository(this._dio);

  final Dio _dio;

  /// The saved list, newest first, with the per-user cap.
  ///
  /// **Fetched separately from the catalogue on purpose** — see
  /// [ApiConfig.favourites]. Never pre-filter what comes back: an item retired
  /// since a favourite was saved still appears, and letting the *order* be the
  /// thing that fails gives the user a reason they can act on, where a
  /// favourite that silently vanished would give them none.
  Future<FavouritesResponse> fetchFavourites({
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiConfig.favourites,
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
      return FavouritesResponse.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Saves [lines] as a favourite, returning the saved row.
  ///
  /// Leave [name] null and the server names it after the drinks, preparation
  /// included — which is why the client never composes a label of its own.
  ///
  /// [lines] is the same [OrderLineDto] the composer builds and `GET
  /// /orders/mine` returns, so saving a past order is a straight repost of that
  /// order's lines (§7.7).
  Future<FavouriteDto> saveFavourite({
    required List<OrderLineDto> lines,
    String? name,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.favourites,
        data: SaveFavouriteRequest(lines: lines, name: name).toJson(),
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
      return FavouriteDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Deletes one of the caller's favourites. `204` on success.
  Future<void> deleteFavourite({
    required int favouriteId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      await _dio.delete<void>(
        ApiConfig.favourite(favouriteId),
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }
}

final favouritesRepositoryProvider = Provider<FavouritesRepository>(
  (ref) => FavouritesRepository(ref.watch(dioProvider)),
);
