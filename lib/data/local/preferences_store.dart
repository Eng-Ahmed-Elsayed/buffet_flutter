import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_token_store.dart';

/// Non-secret preferences: the remembered email, the chosen language, whether
/// biometric unlock is enabled.
///
/// These share the secure store rather than adding a preferences package.
/// Over-protecting a language code costs nothing; the reverse mistake — a
/// `SharedPreferences` dependency sitting in the project, inviting someone to
/// put the token in it — is the one that matters (§5).
///
/// **The token is not here.** It lives in [SecureTokenStore] under its own
/// keys, so sign-out can clear credentials without discarding the user's
/// language choice.
class PreferencesStore {
  const PreferencesStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _emailKey = 'pref_email';
  static const _languageKey = 'pref_language';
  static const _biometricsKey = 'pref_biometrics';

  /// The last successfully used email, so the second sign-in is password-only
  /// and biometric-only after that (§5.1). Not a secret, and never the password.
  Future<String?> readEmail() => _storage.read(key: _emailKey);
  Future<void> writeEmail(String email) =>
      _storage.write(key: _emailKey, value: email);

  Future<String?> readLanguageCode() => _storage.read(key: _languageKey);
  Future<void> writeLanguageCode(String code) =>
      _storage.write(key: _languageKey, value: code);

  Future<bool> readBiometricsEnabled() async =>
      await _storage.read(key: _biometricsKey) == 'true';
  Future<void> writeBiometricsEnabled(bool enabled) =>
      _storage.write(key: _biometricsKey, value: '$enabled');

  /// Clears preferences tied to the signed-in account.
  ///
  /// The language stays — it is a device preference, not an account one, and
  /// snapping the app back to Arabic because someone signed out would be a bug.
  /// The email stays too, deliberately: §5.1 wants the next sign-in prefilled.
  Future<void> clearAccountPreferences() =>
      _storage.delete(key: _biometricsKey);
}

final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => PreferencesStore(ref.watch(secureStorageProvider)),
);
