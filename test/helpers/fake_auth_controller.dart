import 'package:buffet_app/data/api/api_client.dart';
import 'package:buffet_app/data/local/biometric_enrolment_guard.dart';
import 'package:buffet_app/data/local/biometric_service.dart';
import 'package:buffet_app/data/local/preferences_store.dart';
import 'package:buffet_app/data/local/secure_token_store.dart';
import 'package:buffet_app/data/repositories/auth_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// A biometric authenticator that is never actually consulted — the controller
/// below stubs `unlock` — but has to exist to build the real one.
class _InertAuthenticator implements BiometricAuthenticator {
  const _InertAuthenticator();

  @override
  Future<bool> canCheckBiometrics() async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> availableBiometrics() async => const [];

  @override
  Future<bool> authenticate({required String localizedReason}) async => false;
}

/// Holds the auth machine at a chosen stage without touching secure storage or
/// the biometric hardware.
class FakeAuthController extends AuthController {
  FakeAuthController(AuthState initial, {this.pinned = false})
    : super(
        AuthRepository(
          dio: Dio(),
          tokenStore: const SecureTokenStore(FlutterSecureStorage()),
          preferences: const PreferencesStore(FlutterSecureStorage()),
        ),
        AuthEvents(),
        const BiometricService(_InertAuthenticator()),
        const BiometricEnrolmentGuard(),
      ) {
    state = initial;
  }

  /// Holds [state] exactly as given. The controller restores from secure
  /// storage on construction, and storage is mocked here, so without this the
  /// restore lands a moment later and replaces a signed-in identity with an
  /// empty session. Set false once the restore has had its chance, to let a
  /// test's own state change through.
  bool pinned;

  @override
  set state(AuthState value) {
    if (pinned && mounted && super.state.stage != AuthStage.restoring) return;
    super.state = value;
  }

  /// The lock screen prompts on arrival. Report a plain cancellation so the
  /// screen settles into its "unlock failed, here is the way past" state
  /// rather than waiting on a platform channel that does not exist under test.
  @override
  Future<BiometricFailure?> unlock({required String reason}) async =>
      BiometricFailure.cancelled;
}
