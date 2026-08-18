/// API endpoints and transport settings.
abstract final class ApiConfig {
  /// Overridable at build time so a dev build can point elsewhere without a
  /// code change:
  /// `flutter run --dart-define=BUFFET_API_BASE_URL=https://host/api/v1`
  static const baseUrl = String.fromEnvironment(
    'BUFFET_API_BASE_URL',
    defaultValue: 'http://digitalbuffet.runasp.net/api/v1',
  );

  /// The origin, for resolving the relative `imageUrl` values the API returns.
  static String get host {
    final uri = Uri.parse(baseUrl);
    return '${uri.scheme}://${uri.authority}';
  }

  /// Resolves a relative image path against the API host.
  ///
  /// Returns null for a null or empty path so callers fall straight through to
  /// their placeholder. A `404` on the resulting URL is also "use the
  /// fallback" — the uploads folder is not covered by database backups (§7.1).
  static String? imageUrl(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return null;
    if (relativePath.startsWith('http://') ||
        relativePath.startsWith('https://')) {
      return relativePath;
    }
    final path = relativePath.startsWith('/') ? relativePath : '/$relativePath';
    return '$host$path';
  }

  static const connectTimeout = Duration(seconds: 15);
  static const receiveTimeout = Duration(seconds: 20);
  static const sendTimeout = Duration(seconds: 20);

  /// `RequestOptions.extra` key marking a request that must not carry a bearer
  /// token, and whose `401` is a credential failure rather than an expired
  /// session. Login only.
  static const skipAuthFlag = 'skipAuth';

  /// `RequestOptions.extra` key carrying the language for `Accept-Language`.
  static const languageFlag = 'language';

  // Auth
  static const login = '/auth/login';
  static const changePassword = '/auth/change-password';

  // Employee
  static const catalogue = '/catalogue';
  static const orders = '/orders';
  static const myOrders = '/orders/mine';
  static String order(int id) => '/orders/$id';
  static String cancelOrder(int id) => '/orders/$id/cancel';
  static const notifications = '/notifications';
  static const notificationsRead = '/notifications/read';
  static const myMaterials = '/materials/mine';
  static const declareMaterial = '/materials/declare';

  // Staff (§8). Additive — the employee endpoints above are caller-scoped and
  // cannot be reused for staff.
  static const staffQueue = '/staff/queue';
  static String staffOrder(int id) => '/staff/orders/$id';
  static String staffStart(int id) => '/staff/orders/$id/start';
  static String staffReady(int id) => '/staff/orders/$id/ready';
  static String staffComplete(int id) => '/staff/orders/$id/complete';
  static String staffCancel(int id) => '/staff/orders/$id/cancel';

  // Deliberately absent: /staff/declarations*. Those are admin-only — a Staff
  // token gets 403 on all three — and the app must not build a control that
  // cannot succeed (§8.2).

  /// Foreground poll interval for a live order (§7.3).
  static const orderPollInterval = Duration(seconds: 15);

  /// Foreground poll interval for the staff queue (§8.1). Staff keep the
  /// screen open; a stale queue is worse than a slightly chatty one.
  static const queuePollInterval = Duration(seconds: 10);

  /// How long the undo window stays open after a one-tap staff action (§8.1).
  static const undoWindow = Duration(seconds: 5);

  /// `?take=` caps at 200 server-side.
  static const queuePageSize = 50;
}
