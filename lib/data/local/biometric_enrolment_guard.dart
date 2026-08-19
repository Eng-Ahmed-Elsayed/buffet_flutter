import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device's biometric enrolment has changed since unlock was
/// switched on.
enum EnrolmentState {
  /// Unchanged — the same fingerprints and faces as when the user opted in.
  valid,

  /// A biometric was **added or removed**. §6 treats this as untrusted: the
  /// stored token is cleared and a full password sign-in is required. This is
  /// the one case where being strict is right — a colleague who added their
  /// own fingerprint must not inherit the session.
  changed,

  /// Cannot be determined: no secure lock screen, an unsupported platform, or
  /// the sentinel was never armed. Treated as [valid] by callers — signing
  /// users out because a device behaves unusually would be worse than the risk.
  unavailable,
}

/// Detects biometric enrolment changes, which `local_auth` cannot report.
///
/// `local_auth` authenticates without a `CryptoObject`, so the Keystore key
/// Android would invalidate is never involved and
/// `KeyPermanentlyInvalidatedException` never surfaces. This guard creates such
/// a key deliberately — armed with `setInvalidatedByBiometricEnrollment(true)`,
/// Android destroys it the moment enrolment changes, and the failure to use it
/// is the signal.
///
/// **Android only.** iOS has an equivalent in `LAContext.evaluatedPolicyDomainState`,
/// but it is not wired up: the Keychain item is already
/// `first_unlock_this_device` and does not sync, and the App Store review
/// surface for a second native path is not worth it until iOS ships. On iOS
/// every call reports [EnrolmentState.unavailable], which callers treat as
/// "carry on" — matching today's behaviour exactly.
class BiometricEnrolmentGuard {
  const BiometricEnrolmentGuard([this._channel = _defaultChannel]);

  static const _defaultChannel = MethodChannel('buffet/biometric_enrolment');

  final MethodChannel _channel;

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// Pins the current enrolment. Called when the user turns unlock **on**.
  Future<void> arm() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('arm');
    } on PlatformException {
      // A device with no secure lock screen cannot hold the key. Not an error:
      // the protection is simply unavailable and check() will say so.
    } on MissingPluginException {
      // Running under a test harness or an older build of the host.
    }
  }

  /// Reports whether enrolment changed since [arm].
  Future<EnrolmentState> check() async {
    if (!_supported) return EnrolmentState.unavailable;
    try {
      final name = await _channel.invokeMethod<String>('check');
      return switch (name) {
        'VALID' => EnrolmentState.valid,
        'CHANGED' => EnrolmentState.changed,
        _ => EnrolmentState.unavailable,
      };
    } on PlatformException {
      return EnrolmentState.unavailable;
    } on MissingPluginException {
      return EnrolmentState.unavailable;
    }
  }

  /// Drops the sentinel. Called when unlock is turned **off** or on sign-out.
  Future<void> disarm() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('disarm');
    } on PlatformException {
      // Nothing to clean up.
    } on MissingPluginException {
      // Nothing to clean up.
    }
  }
}

final biometricEnrolmentGuardProvider = Provider<BiometricEnrolmentGuard>(
  (ref) => const BiometricEnrolmentGuard(),
);
