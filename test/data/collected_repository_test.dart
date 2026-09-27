import 'dart:convert';

import 'package:buffet_app/data/api/api_exception.dart';
import 'package:buffet_app/data/repositories/order_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with [status] and [body], and records what was sent.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, [this.body = '']);

  final int status;
  final String body;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

OrderRepository _repository(_Adapter adapter) => OrderRepository(
  Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
    ..httpClientAdapter = adapter,
);

void main() {
  test('"I picked it up" posts to the order\'s collected route', () async {
    final adapter = _Adapter(204);
    await _repository(adapter).confirmCollected(
      orderId: 70,
      languageCode: 'ar',
      networkErrorFallback: '',
    );
    expect(adapter.requests.single.method, 'POST');
    expect(adapter.requests.single.path, '/orders/70/collected');
  });

  test("a refusal carries the server's own words (§4)", () async {
    final adapter = _Adapter(
      400,
      jsonEncode({'message': 'الطلب ليس للاستلام'}),
    );
    expect(
      () => _repository(adapter).confirmCollected(
        orderId: 70,
        languageCode: 'ar',
        networkErrorFallback: '',
      ),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'الطلب ليس للاستلام',
        ),
      ),
    );
  });
}
