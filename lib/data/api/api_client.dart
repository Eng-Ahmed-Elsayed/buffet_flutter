import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local/secure_token_store.dart';
import 'api_config.dart';

/// Signals that the stored token was rejected, so the router can send the user
/// to login. Broadcast because more than one screen may be listening.
class AuthEvents {
  final _controller = StreamController<void>.broadcast();

  Stream<void> get onUnauthorized => _controller.stream;

  void signalUnauthorized() => _controller.add(null);

  void dispose() => unawaited(_controller.close());
}

final authEventsProvider = Provider<AuthEvents>((ref) {
  final events = AuthEvents();
  ref.onDispose(events.dispose);
  return events;
});

/// The single Dio instance. Every request in the app goes through here.
///
/// Three things happen centrally so no caller has to remember them:
/// the bearer token, the `Accept-Language` header, and `401` handling.
final dioProvider = Provider<Dio>((ref) {
  final tokenStore = ref.watch(secureTokenStoreProvider);
  final events = ref.watch(authEventsProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      sendTimeout: ApiConfig.sendTimeout,
      // Non-2xx must reach onError so the interceptor can act on 401 and the
      // repository can read the server's message. 200 and 201 are both success
      // for an order placement, so the range covers them together.
      validateStatus: (status) => status != null && status >= 200 && status < 300,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );

  dio.interceptors.add(
    QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        // Login is the one endpoint that must not carry a stale bearer.
        if (options.extra[ApiConfig.skipAuthFlag] != true) {
          final token = await tokenStore.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }

        // Error messages are localised server-side from this header (§4).
        options.headers['Accept-Language'] =
            options.extra[ApiConfig.languageFlag] as String? ?? 'ar';

        handler.next(options);
      },

      onError: (error, handler) async {
        // §4.4: map 401 centrally — clear the token, route to login, do NOT
        // retry. There is no refresh endpoint to retry against, so a retry
        // loop here would just replay a dead token until the timeout.
        if (error.response?.statusCode == 401 &&
            error.requestOptions.extra[ApiConfig.skipAuthFlag] != true) {
          await tokenStore.clear();
          events.signalUnauthorized();
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});
