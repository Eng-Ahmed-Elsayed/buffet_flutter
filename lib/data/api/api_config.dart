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

  /// The forced first-run path, which asks for no current password: the token
  /// reaching it was minted by signing in with that password moments earlier.
  static const setInitialPassword = '/auth/set-initial-password';

  // Employee
  static const catalogue = '/catalogue';
  static const orders = '/orders';
  static const myOrders = '/orders/mine';
  static String order(int id) => '/orders/$id';
  static String cancelOrder(int id) => '/orders/$id/cancel';

  /// The caller's saved orders. **Deliberately not bundled into
  /// [catalogue]**, which is cached and refreshed on resume: this list changes
  /// the moment the user saves one, and a just-saved favourite invisible until
  /// the next resume is worse than the extra round trip (§7.6).
  static const favourites = '/favourites';

  /// `204` on success and **`404`** — never `403` — for someone else's, the
  /// same convention as [order].
  static String favourite(int id) => '/favourites/$id';

  static const notifications = '/notifications';
  static const notificationsRead = '/notifications/read';

  /// Registers (POST) and unregisters (DELETE, `?token=`) this device for push.
  ///
  /// Register is idempotent and called on every launch; the server upserts on
  /// the token. Unregister must run while the bearer is still valid — a shared
  /// device that keeps receiving the previous user's orders is a privacy
  /// failure, not an inconvenience.
  static const registerDevice = '/notifications/device';
  static const myMaterials = '/materials/mine';
  static const declareMaterial = '/materials/declare';

  /// For an item the buffet does not carry: creates the private catalogue
  /// entry and the declaration together. **`quantity` here is packages**, not
  /// base units as on [declareMaterial].
  static const declareNewMaterial = '/materials/declare-new';

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
  ///
  /// **Not made redundant by push.** Push closes the *closed-app* gap; polling
  /// closes the *foreground freshness* gap, and this screen is open precisely
  /// because someone is watching it. Removing this would make the screen the
  /// user is staring at slower than their notification shade.
  static const orderPollInterval = Duration(seconds: 15);

  /// Foreground poll interval for the staff queue (§8.1). Staff keep the
  /// screen open; a stale queue is worse than a slightly chatty one.
  ///
  /// Push does not replace this either: staff receive no pushes at all, and the
  /// queue is a shared multi-user view where polling is the only way one staff
  /// member sees another's actions.
  static const queuePollInterval = Duration(seconds: 10);

  /// How long the undo window stays open after a one-tap staff action (§8.1).
  static const undoWindow = Duration(seconds: 5);

  /// The same window when a screen reader is driving.
  ///
  /// A timed affordance carrying the only way out of an action is a WCAG 2.2
  /// SC 2.2.1 problem; Flutter's own SnackBar stops timing out under
  /// TalkBack/VoiceOver for exactly this reason. Someone reading a card aloud
  /// is not racing a clock, so the window stretches rather than the control
  /// vanishing mid-sentence.
  static const undoWindowAccessible = Duration(seconds: 20);

  /// `?take=` caps at 200 server-side.
  static const queuePageSize = 50;
}
