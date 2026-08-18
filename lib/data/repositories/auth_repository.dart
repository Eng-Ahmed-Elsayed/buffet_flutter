import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../api/api_exception.dart';
import '../local/preferences_store.dart';
import '../local/secure_token_store.dart';
import '../models/auth_models.dart';

/// Sign-in, sign-out and password change.
///
/// Widgets never call the API directly — they go through here, which is what
/// keeps token storage and the `401` rule in one place (§3).
class AuthRepository {
  const AuthRepository({
    required this._dio,
    required this._tokenStore,
    required this._preferences,
  });

  final Dio _dio;
  final SecureTokenStore _tokenStore;
  final PreferencesStore _preferences;

  /// Signs in and stores the token.
  ///
  /// The `401` here is a *credential* failure, not an expired session, so the
  /// request is flagged to skip the central interceptor — otherwise a wrong
  /// password would fire the "your session ended" path.
  ///
  /// The server returns the same message for a wrong password and a disabled
  /// account so the endpoint cannot be used to discover which accounts exist.
  /// The client does not try to be more specific (§5.1).
  Future<LoginResponse> login({
    required String username,
    required String password,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiConfig.login,
        data: LoginRequest(username: username, password: password).toJson(),
        options: Options(
          extra: {
            ApiConfig.skipAuthFlag: true,
            ApiConfig.languageFlag: languageCode,
          },
        ),
      );

      final login = LoginResponse.fromJson(response.data!);

      await _tokenStore.write(token: login.token, expiresUtc: login.expiresUtc);
      // Not a secret, and §5.1 wants the next sign-in prefilled.
      await _preferences.writeEmail(username);

      return login;
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Changes the password. Returns normally on `204`.
  ///
  /// Serves both the forced first-run case and the voluntary one from
  /// settings. The server's `400` message is surfaced as-is — it is already in
  /// the user's language (§5.2).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    try {
      await _dio.post<void>(
        ApiConfig.changePassword,
        data: ChangePasswordRequest(
          currentPassword: currentPassword,
          newPassword: newPassword,
        ).toJson(),
        options: Options(extra: {ApiConfig.languageFlag: languageCode}),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error, networkErrorFallback);
    }
  }

  /// Clears the token and any account-scoped preferences.
  ///
  /// The remembered email and the language survive deliberately — they make
  /// the next sign-in easier and are not credentials.
  Future<void> signOut() async {
    await _tokenStore.clear();
    await _preferences.clearAccountPreferences();
  }

  Future<bool> hasValidToken() => _tokenStore.hasValidToken();

  Future<String?> rememberedEmail() => _preferences.readEmail();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    dio: ref.watch(dioProvider),
    tokenStore: ref.watch(secureTokenStoreProvider),
    preferences: ref.watch(preferencesStoreProvider),
  ),
);
