import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/api/api_exception.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/repositories/order_repository.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/error_text.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final _l10n = lookupAppLocalizations(const Locale('ar'));

DioException _failure({Object? body, int? status}) {
  final request = RequestOptions(path: '/orders');
  return DioException(
    requestOptions: request,
    response: status == null
        ? null
        : Response<Object?>(
            requestOptions: request,
            statusCode: status,
            data: body,
          ),
  );
}

void main() {
  group('a failure is worded by what actually happened', () {
    test('a server error with no message is not called a network fault', () {
      // An HTML error page from a crashed or restarting server.
      final error = ApiException.fromDio(
        _failure(status: 500, body: '<html>Service Unavailable</html>'),
        _l10n.networkError,
      );
      expect(describeError(error, _l10n), _l10n.genericError);
    });

    test('no response at all is the network message', () {
      final error = ApiException.fromDio(_failure(), _l10n.networkError);
      expect(describeError(error, _l10n), _l10n.networkError);
    });

    test("the server's own message is shown as it is", () {
      final error = ApiException.fromDio(
        _failure(status: 400, body: {'message': 'تجاوزت حد البوفيه'}),
        _l10n.networkError,
      );
      expect(describeError(error, _l10n), 'تجاوزت حد البوفيه');
    });
  });

  group('a status this build does not know', () {
    test('is unknown, never Pending, and offers no action', () {
      final status = OrderStatus.fromWire('Archived');
      expect(status, OrderStatus.unknown);
      expect(status.isCancellable, isFalse);
      expect(status.isSettled, isFalse);
    });
  });

  group('the Orders tab asks for its whole history', () {
    test('GET /orders/mine names take, at the server maximum', () async {
      final dio = Dio();
      RequestOptions? sent;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            sent = options;
            handler.resolve(
              Response<List<dynamic>>(requestOptions: options, data: const []),
            );
          },
        ),
      );
      await OrderRepository(dio).fetchMyOrders(
        languageCode: 'ar',
        networkErrorFallback: '',
      );
      expect(sent!.path, ApiConfig.myOrders);
      expect(sent!.queryParameters['take'], 100);
    });
  });
}
