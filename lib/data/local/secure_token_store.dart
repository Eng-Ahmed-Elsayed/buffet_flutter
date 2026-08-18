import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The only place the JWT is ever written.
///
/// **Never `SharedPreferences`** (§5): that is world-readable on a rooted
/// device and backed up off the handset. This goes to the Keychain on iOS and
/// the Keystore-backed EncryptedSharedPreferences on Android.
///
/// Tokens last 30 days and there is no refresh endpoint, so a leaked one is
/// valid for a long time. Nothing here is ever logged — not the token, not a
/// prefix of it, not while debugging.
class SecureTokenStore {
  const SecureTokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'auth_token';
  static const _expiryKey = 'auth_expires_utc';

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  /// Stores the token and the expiry that came with it.
  ///
  /// The expiry is kept so the router can send an obviously-dead token to the
  /// login screen without spending a round trip to be told `401`.
  Future<void> write({required String token, required DateTime expiresUtc}) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(
      key: _expiryKey,
      value: expiresUtc.toUtc().toIso8601String(),
    );
  }

  Future<DateTime?> readExpiry() async {
    final raw = await _storage.read(key: _expiryKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  /// True when there is a token that has not already expired.
  ///
  /// A token missing its expiry is treated as usable rather than discarded —
  /// the server is the authority, and a central `401` interceptor will clear it
  /// the moment it is actually rejected.
  Future<bool> hasValidToken() async {
    final token = await readToken();
    if (token == null || token.isEmpty) return false;

    final expiry = await readExpiry();
    if (expiry == null) return true;
    return expiry.isAfter(DateTime.now().toUtc());
  }

  /// Called on sign-out and centrally on any `401`.
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiryKey);
  }
}

/// The one configured storage instance, shared by [SecureTokenStore] and
/// `PreferencesStore` so the platform options are declared exactly once.
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    // §11: `encryptedSharedPreferences: true` is REQUIRED and defaults to
    // false. Without it the plugin falls back to a plain preferences file
    // and the token is readable on a rooted device.
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // §11: `first_unlock_this_device` — readable after the first unlock
    // following a reboot, and **never synced to iCloud**, so the token does
    // not travel to the user's other devices.
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  ),
);

final secureTokenStoreProvider = Provider<SecureTokenStore>(
  (ref) => SecureTokenStore(ref.watch(secureStorageProvider)),
);
