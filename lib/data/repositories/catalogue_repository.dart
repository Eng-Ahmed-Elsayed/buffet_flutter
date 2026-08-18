import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_exception.dart';
import '../models/catalogue_models.dart';
import '../models/order_models.dart';

/// The catalogue and order placement.
class CatalogueRepository {
  const CatalogueRepository(this._dio);

  final Dio _dio;

  /// Everything the order screen needs, in one round trip.
  Future<CatalogueResponse> fetchCatalogue({
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiConfig.catalogue,
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
      return CatalogueResponse.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Places an order.
  ///
  /// **Both `201 duplicate:false` and `200 duplicate:true` are success** — the
  /// second means a retry matched an existing order, which is exactly what the
  /// idempotency key is for. The caller shows the same confirmation either way.
  ///
  /// There is deliberately **no offline queue**: a failure here keeps the
  /// composer filled so the user can retry with the *same* key. Silently
  /// holding an order to send later would deliver a coffee nobody is waiting
  /// for (§9).
  Future<PlaceOrderResponse> placeOrder({
    required PlaceOrderApiRequest request,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.orders,
        data: request.toJson(),
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
      return PlaceOrderResponse.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }
}

final catalogueRepositoryProvider = Provider<CatalogueRepository>(
  (ref) => CatalogueRepository(ref.watch(dioProvider)),
);
