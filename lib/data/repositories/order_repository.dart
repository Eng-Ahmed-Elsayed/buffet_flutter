import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_exception.dart';
import '../models/order_models.dart';

/// The caller's own orders. Every endpoint here is caller-scoped: `/orders/{id}`
/// 404s on anyone else's order, deliberately (a 403 would confirm it exists).
class OrderRepository {
  const OrderRepository(this._dio);

  final Dio _dio;

  Future<OrderSummaryDto> fetchOrder({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiConfig.order(orderId),
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
      return OrderSummaryDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  Future<List<OrderSummaryDto>> fetchMyOrders({
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        ApiConfig.myOrders,
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
      return (response.data ?? [])
          .map((e) => OrderSummaryDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Cancels the caller's own order.
  ///
  /// **Pending-only and ownership-checked.** The UI hides the action once the
  /// status leaves `Pending` rather than showing a button that will 400.
  Future<void> cancelOrder({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      await _dio.post<void>(
        ApiConfig.cancelOrder(orderId),
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }
}

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(ref.watch(dioProvider)),
);
