import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

/// Why a biometric prompt did not succeed.
///
/// Each case strands the user differently, so they are distinguished here
/// rather than collapsed into a bool (§6).
enum BiometricFailure {
  /// The user dismissed the prompt, or the finger was not recognised. They are
  /// still who they were — offer the prompt again, and a way past it.
  cancelled,

  /// No fingerprint or face is enrolled, or there is no device passcode. The
  /// caller turns the preference **off** and falls back to a password: leaving
  /// a flag set for hardware that cannot satisfy it locks the user out.
  unavailable,

  /// Too many attempts. Only a device credential clears it, so retrying the
  /// prompt is pointless — the caller must route to password sign-in.
  lockedOut,
}

/// The outcome of a biometric prompt.
class BiometricResult {
  const BiometricResult.success() : failure = null;
  const BiometricResult.failed(this.failure);

  final BiometricFailure? failure;

  bool get succeeded => failure == null;
}

/// The slice of `local_auth` this app uses.
///
/// Exists so the auth flow can be tested without a fingerprint reader and
/// without depending on the plugin's platform-interface package: the seam is
/// owned here rather than borrowed from a transitive dependency.
abstract interface class BiometricAuthenticator {
  Future<bool> canCheckBiometrics();
  Future<bool> isDeviceSupported();
  Future<List<BiometricType>> availableBiometrics();
  Future<bool> authenticate({required String localizedReason});
}

/// The real implementation, calling the plugin.
class PluginBiometricAuthenticator implements BiometricAuthenticator {
  PluginBiometricAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> canCheckBiometrics() => _auth.canCheckBiometrics;

  @override
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  @override
  Future<List<BiometricType>> availableBiometrics() =>
      _auth.getAvailableBiometrics();

  @override
  Future<bool> authenticate({required String localizedReason}) =>
      _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          // A wet finger must not lock someone out of their coffee: the device
          // PIN is an acceptable way through (§6).
          biometricOnly: false,
          // Survive the app being backgrounded mid-prompt.
          stickyAuth: true,
        ),
      );
}

/// Wraps `local_auth`.
///
/// **Biometrics unlock a stored token; they are not a second factor.** The
/// server knows nothing about the fingerprint, and no call here makes an
/// expired token valid — the first `401` still routes to login (§6).
///
/// Exists as a seam so the auth flow can be tested without a fingerprint
/// reader, and so the plugin's `PlatformException` codes are translated once
/// rather than at every call site.
class BiometricService {
  const BiometricService(this._auth);

  final BiometricAuthenticator _auth;

  /// Whether this device can satisfy a prompt at all.
  ///
  /// `isDeviceSupported()` is included deliberately: it covers the PIN and
  /// pattern fallback, and a device with a passcode but no fingerprint can
  /// still unlock a token. Requiring biometric hardware would exclude it for
  /// no benefit.
  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics() ||
          await _auth.isDeviceSupported();
    } on PlatformException {
      // A platform that cannot answer the question cannot satisfy a prompt
      // either. Reporting "unavailable" is the safe reading — it falls back to
      // a password rather than offering a control that will fail.
      return false;
    }
  }

  /// Which biometrics are enrolled, so the caller can label the control with
  /// what the user will actually see (face vs fingerprint).
  Future<List<BiometricType>> enrolledTypes() async {
    try {
      return await _auth.availableBiometrics();
    } on PlatformException {
      return const [];
    }
  }

  /// Prompts, and translates the plugin's error codes into [BiometricFailure].
  ///
  /// [reason] is shown by the OS and must arrive already localised — it is
  /// user-facing text, so it comes from the ARB files, never from here.
  Future<BiometricResult> authenticate({required String reason}) async {
    try {
      final ok = await _auth.authenticate(localizedReason: reason);
      return ok
          ? const BiometricResult.success()
          : const BiometricResult.failed(BiometricFailure.cancelled);
    } on PlatformException catch (error) {
      return BiometricResult.failed(_failureFor(error.code));
    }
  }

  BiometricFailure _failureFor(String code) => switch (code) {
    auth_error.notEnrolled ||
    auth_error.notAvailable ||
    auth_error.passcodeNotSet ||
    auth_error.otherOperatingSystem => BiometricFailure.unavailable,
    auth_error.lockedOut ||
    auth_error.permanentlyLockedOut => BiometricFailure.lockedOut,
    // An unrecognised code is treated as a dismissal rather than as broken
    // hardware: the user keeps the prompt and the way past it, and no
    // preference is silently switched off on a code we do not understand.
    _ => BiometricFailure.cancelled,
  };
}

final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(PluginBiometricAuthenticator()),
);
