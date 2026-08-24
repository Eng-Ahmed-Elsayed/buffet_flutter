import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';

/// Registers this device for push, and drops the registration on sign-out.
///
/// **Android only.** iOS push needs a paid Apple Developer account for APNs and
/// there is no budget for one (§7.4), so nothing here runs on an iPhone — it
/// falls back to the local alerts and the notification list, which work on both
/// platforms. Everything except that guard is platform-neutral, so adding iOS
/// later is a config change rather than a rewrite.
///
/// Driven by the auth stage rather than by `main()`, because a token is
/// meaningless without a signed-in user to attach it to.
class PushController {
  PushController(this._dio);

  final Dio _dio;

  StreamSubscription<String>? _refreshSubscription;
  String? _registeredToken;

  /// Whether push is even possible here.
  ///
  /// Guards every entry point rather than each caller remembering to.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Asks permission, gets a token, and tells the server about it.
  ///
  /// Idempotent — call it on every transition into `signedIn`. The server
  /// upserts on the token, so a device that has already registered simply has
  /// its `lastSeenAtUtc` refreshed.
  Future<void> register() async {
    if (!isSupported) return;

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        // A normal outcome, not an error. The notification list and the
        // outstanding-order card still carry everything.
        return;
      }

      final token = await messaging.getToken();
      if (token == null) return;

      await _send(token);

      // FCM reissues a token on reinstall, restore, or a data clear. Without
      // this the server would keep pushing to a value that no longer exists.
      await _refreshSubscription?.cancel();
      _refreshSubscription = messaging.onTokenRefresh.listen((fresh) {
        unawaited(_send(fresh));
      });
    } on Object catch (error) {
      // Never allowed to break sign-in. Push is an enhancement over the
      // notification list, and a user who cannot receive one must still be able
      // to order a drink.
      debugPrint('Could not register for push: $error');
    }
  }

  Future<void> _send(String token) async {
    try {
      await _dio.post<void>(
        ApiConfig.registerDevice,
        data: {
          'token': token,
          'platform': Platform.isAndroid ? 'android' : 'ios',
        },
      );
      _registeredToken = token;
    } on DioException catch (error) {
      debugPrint('Could not register the device token: ${error.message}');
    }
  }

  /// Drops this device's registration.
  ///
  /// **Must run while the bearer token is still valid**, which is why the auth
  /// controller calls it through `onBeforeSignOut` rather than afterwards. A
  /// shared counter device that keeps receiving the previous user's orders is a
  /// privacy failure, not an inconvenience.
  Future<void> unregister() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;

    final token = _registeredToken;
    _registeredToken = null;
    if (!isSupported || token == null) return;

    try {
      await _dio.delete<void>(
        ApiConfig.registerDevice,
        queryParameters: {'token': token},
      );
      // Locally too, so a new sign-in on this device gets a fresh token rather
      // than one the server has just been told to forget.
      await FirebaseMessaging.instance.deleteToken();
    } on Object catch (error) {
      debugPrint('Could not unregister the device token: $error');
    }
  }
}

final pushControllerProvider = Provider<PushController>(
  (ref) => PushController(ref.watch(dioProvider)),
);
