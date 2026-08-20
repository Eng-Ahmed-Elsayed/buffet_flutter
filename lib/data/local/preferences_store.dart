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
  static const _roleKey = 'pref_role';
  static const _displayNameKey = 'pref_display_name';
  static const _departmentKey = 'pref_department';
  static const _guestsKey = 'pref_can_order_for_guests';
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

  /// The signed-in user's role, display name and department.
  ///
  /// **Not credentials** — the token is the credential, and the server decides
  /// what a token may do. These are cached only so a restored session can draw
  /// the same screens as a fresh one: without the role, a Staff member
  /// restarting the app was routed to the employee catalogue and the router
  /// actively bounced them away from the queue, because a session restored
  /// from storage carries no login response to read it from.
  Future<void> writeIdentity({
    required String role,
    required String displayName,
    required String department,
    required bool canOrderForGuests,
  }) async {
    await _storage.write(key: _roleKey, value: role);
    await _storage.write(key: _displayNameKey, value: displayName);
    await _storage.write(key: _departmentKey, value: department);
    await _storage.write(key: _guestsKey, value: '$canOrderForGuests');
  }

  Future<
    ({
      String role,
      String displayName,
      String department,
      bool canOrderForGuests,
    })?
  >
  readIdentity() async {
    final role = await _storage.read(key: _roleKey);
    if (role == null) return null;
    return (
      role: role,
      displayName: await _storage.read(key: _displayNameKey) ?? '',
      department: await _storage.read(key: _departmentKey) ?? '',
      // Absent for an identity cached before this key existed. False is the
      // safe reading: the guest field stays hidden until the next sign-in
      // rather than being offered to someone the server will reject.
      canOrderForGuests: await _storage.read(key: _guestsKey) == 'true',
    );
  }

  Future<bool> readBiometricsEnabled() async =>
      await _storage.read(key: _biometricsKey) == 'true';
  Future<void> writeBiometricsEnabled(bool enabled) =>
      _storage.write(key: _biometricsKey, value: '$enabled');

  /// Clears preferences tied to the signed-in account.
  ///
  /// The language stays — it is a device preference, not an account one, and
  /// snapping the app back to Arabic because someone signed out would be a bug.
  /// The email stays too, deliberately: §5.1 wants the next sign-in prefilled.
  Future<void> clearAccountPreferences() async {
    await _storage.delete(key: _biometricsKey);
    // The identity goes with the session it describes — leaving a role behind
    // would route the NEXT user of this device by the previous one's.
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _displayNameKey);
    await _storage.delete(key: _departmentKey);
    await _storage.delete(key: _guestsKey);
  }
}

final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => PreferencesStore(ref.watch(secureStorageProvider)),
);
