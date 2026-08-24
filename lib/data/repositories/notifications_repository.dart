import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_exception.dart';
import '../models/order_models.dart';

/// The caller's own notifications.
///
/// These rows are the **system of record**, not a mirror of the notification
/// shade: the server writes one before it attempts a push, so a push that was
/// throttled, dropped, or never permitted is still recoverable here. They are
/// also the only place three kinds ever surface — `LowStock`,
/// `DeclarationConfirmed` and `DeclarationRejected` deliberately get no push
/// (§7.4), because they are information for next time the app opens.
class NotificationsRepository {
  const NotificationsRepository(this._dio);

  final Dio _dio;

  Future<List<NotificationDto>> fetch({
    required String languageCode,
    required String networkErrorFallback,
    bool unreadOnly = false,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        ApiConfig.notifications,
        queryParameters: unreadOnly ? const {'unreadOnly': true} : null,
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
      return (response.data ?? [])
          .map((e) => NotificationDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Marks **every** notification read.
  ///
  /// The endpoint takes no ids — it is all or nothing. The server's
  /// `MarkNotificationsReadAsync` does accept a list, so per-row marking is
  /// available if the badge ever needs to be finer, but nothing exposes it yet.
  Future<void> markAllRead({
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      await _dio.post<void>(
        ApiConfig.notificationsRead,
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(dioProvider)),
);
