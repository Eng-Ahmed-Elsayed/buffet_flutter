import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_exception.dart';
import '../models/order_models.dart';
import '../models/staff_models.dart';

/// The staff queue. Additive to the employee surface — the employee endpoints
/// are caller-scoped and cannot be reused here (§0).
class QueueRepository {
  const QueueRepository(this._dio);

  final Dio _dio;

  /// The work queue: **`Pending` + `InProgress` only**, oldest first.
  ///
  /// An order marked `Ready` disappears from this list — that is not a bug.
  /// Use [fetchReadyForHandover] for the collection list.
  Future<List<StaffOrderDto>> fetchQueue({
    required String languageCode,
    required String networkErrorFallback,
  }) => _fetch(
    status: null,
    languageCode: languageCode,
    networkErrorFallback: networkErrorFallback,
  );

  /// The handover list — orders made but not yet collected.
  ///
  /// A separate fetch because the default queue excludes `Ready`. An order
  /// served with `deliverNow` never enters this state at all.
  Future<List<StaffOrderDto>> fetchReadyForHandover({
    required String languageCode,
    required String networkErrorFallback,
  }) => _fetch(
    status: OrderStatus.ready.wire,
    languageCode: languageCode,
    networkErrorFallback: networkErrorFallback,
  );

  Future<List<StaffOrderDto>> _fetch({
    required String? status,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        ApiConfig.staffQueue,
        queryParameters: {
          if (status != null) 'status': status,
          'take': ApiConfig.queuePageSize,
        },
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
      return (response.data ?? [])
          .map((e) => StaffOrderDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  Future<void> start({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      await _dio.post<void>(
        ApiConfig.staffStart(orderId),
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Marks an order `Ready` — **the only path that deducts stock**.
  ///
  /// `Ready` means the drink was physically made; `Completed` means it was
  /// handed over. This endpoint delegates to `OrderServingService`, the one
  /// component that knows whose jar each component comes from, and writes the
  /// ledger rows.
  ///
  /// [deliverNow] serves and completes in one call — the common case at the
  /// counter, offered as the primary action.
  ///
  /// **Shortages come back as `200` with a populated `warnings` array, never
  /// `400`.** A result with warnings is still success: the drink was made.
  /// Surface the warnings on the card; never treat them as a failure, and
  /// never disable this action on a stock reading.
  Future<ServeResultDto> markReady({
    required int orderId,
    required bool deliverNow,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.staffReady(orderId),
        queryParameters: {if (deliverNow) 'deliverNow': true},
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
      return ServeResultDto.fromJson(response.data!);
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Hands over an order already in `Ready`. Stock was deducted at `/ready`;
  /// this only stamps the status.
  Future<void> complete({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      await _dio.post<void>(
        ApiConfig.staffComplete(orderId),
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Cancels with a reason.
  ///
  /// Cancelling a `Ready` order reverses the consumption and re-books it as
  /// waste — the balance is unchanged, but nobody is credited with a drink they
  /// never received.
  Future<void> cancel({
    required int orderId,
    required String? reason,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      await _dio.post<void>(
        ApiConfig.staffCancel(orderId),
        data: CancelOrderRequest(reason: reason).toJson(),
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  // No declarations methods. GET/POST /staff/declarations* are admin-only and a
  // Staff token gets 403 on all three — separation of duties, not an oversight.
  // Confirming a handover creates stock out of somebody's word, so the person
  // who takes the jar must not also be the only person who signs for it (§8.2).
}

final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => QueueRepository(ref.watch(dioProvider)),
);
