import 'package:buffet_app/data/api/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException dioError({
  int? statusCode,
  Object? body,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final options = RequestOptions(path: '/anything');
  return DioException(
    requestOptions: options,
    type: type,
    response: statusCode == null
        ? null
        : Response<Object?>(
            requestOptions: options,
            statusCode: statusCode,
            data: body,
          ),
  );
}

void main() {
  const fallback = 'تعذّر الاتصال بالخادم.';

  group("the server's message is surfaced as-is", () {
    test('a 400 message is used verbatim, not mapped to a client string', () {
      // §4.4: the message is already localised server-side. Mapping status
      // codes to our own wording would discard something more specific than
      // anything the client could invent.
      final error = ApiException.fromDio(
        dioError(
          statusCode: 400,
          body: {'message': 'الكمية يجب أن تكون أكبر من صفر.'},
        ),
        fallback,
      );

      expect(error.message, 'الكمية يجب أن تكون أكبر من صفر.');
      expect(error.statusCode, 400);
      expect(error.isValidationFailure, isTrue);
    });

    test('a 401 message is used verbatim too', () {
      final error = ApiException.fromDio(
        dioError(
          statusCode: 401,
          body: {'message': 'البريد الإلكتروني أو كلمة المرور غير صحيحة.'},
        ),
        fallback,
      );

      expect(error.message, 'البريد الإلكتروني أو كلمة المرور غير صحيحة.');
      expect(error.isUnauthorized, isTrue);
    });

    test('404 is "not found OR not yours" — the API does not distinguish', () {
      // A 403 would confirm the order exists, so the server deliberately
      // returns 404 for someone else's order.
      final error = ApiException.fromDio(
        dioError(statusCode: 404, body: {'message': 'الطلب غير موجود.'}),
        fallback,
      );

      expect(error.isNotFound, isTrue);
      expect(error.message, 'الطلب غير موجود.');
    });
  });

  group('the fallback is used only when there is nothing to surface', () {
    test('a connection that never reached the server', () {
      final error = ApiException.fromDio(
        dioError(type: DioExceptionType.connectionError),
        fallback,
      );

      expect(error.message, fallback);
      expect(error.isNetworkFailure, isTrue);
      expect(error.statusCode, isNull);
    });

    test('a timeout', () {
      final error = ApiException.fromDio(
        dioError(type: DioExceptionType.connectionTimeout),
        fallback,
      );
      expect(error.isNetworkFailure, isTrue);
    });

    test('a body in an unexpected shape', () {
      final error = ApiException.fromDio(
        dioError(statusCode: 500, body: 'a bare string, not the usual object'),
        fallback,
      );

      expect(error.message, fallback);
      // There WAS a response, so this is not a network failure.
      expect(error.isNetworkFailure, isFalse);
      expect(error.statusCode, 500);
    });

    test('an empty message string does not blank the UI', () {
      final error = ApiException.fromDio(
        dioError(statusCode: 500, body: {'message': '   '}),
        fallback,
      );
      expect(error.message, fallback);
    });

    test('a missing message key', () {
      final error = ApiException.fromDio(
        dioError(statusCode: 500, body: {'error': 'wrong key'}),
        fallback,
      );
      expect(error.message, fallback);
    });
  });

  group('status classification', () {
    test('only 401 is unauthorized', () {
      for (final code in [400, 403, 404, 500]) {
        final error = ApiException.fromDio(
          dioError(statusCode: code, body: {'message': 'x'}),
          fallback,
        );
        expect(error.isUnauthorized, isFalse, reason: 'status $code');
      }
    });
  });
}
