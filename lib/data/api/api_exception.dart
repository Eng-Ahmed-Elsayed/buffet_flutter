import 'package:dio/dio.dart';

/// Every API failure, reduced to one type the UI can render.
///
/// The API returns `{"message": "…"}` on every failure — one shape to parse —
/// and **that message is already localised server-side** from the
/// `Accept-Language` header. Surface it as-is rather than mapping status codes
/// to client strings; the server knows things the client does not (§4.4).
class ApiException implements Exception {
  const ApiException({
    required this.message,
    required this.statusCode,
    this.isNetworkFailure = false,
  });

  /// Builds an exception from a Dio failure, preferring the server's message.
  ///
  /// [fallback] is used only when there is genuinely no message to show — a
  /// connection that never reached the server, or a body in an unexpected
  /// shape.
  factory ApiException.fromDio(DioException error, String fallback) {
    final response = error.response;
    final data = response?.data;

    if (data is Map && data['message'] is String) {
      final message = data['message'] as String;
      if (message.trim().isNotEmpty) {
        return ApiException(
          message: message,
          statusCode: response?.statusCode,
        );
      }
    }

    return ApiException(
      message: fallback,
      statusCode: response?.statusCode,
      isNetworkFailure: response == null,
    );
  }

  /// Ready to display. Never a status code, never an English default when the
  /// server had something to say.
  final String message;

  final int? statusCode;

  /// True when the request never got a response — the only case where the app
  /// substitutes its own wording.
  final bool isNetworkFailure;

  /// `401` — bad credentials or an expired token. Handled centrally by the
  /// interceptor, which clears the token and routes to login.
  bool get isUnauthorized => statusCode == 401;

  /// `404` — not found *or not yours*. The API deliberately does not
  /// distinguish: a `403` would confirm the order exists.
  bool get isNotFound => statusCode == 404;

  /// `400` — validation or a business rule. The message is the whole story.
  bool get isValidationFailure => statusCode == 400;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
