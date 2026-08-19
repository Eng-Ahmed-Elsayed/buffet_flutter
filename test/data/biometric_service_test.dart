import 'package:buffet_app/data/local/biometric_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

/// Stands in for the plugin so the real [BiometricService] runs under test.
///
/// The translation from platform error codes to [BiometricFailure] is the part
/// worth covering, so it is exercised rather than re-implemented here.
class _FakeAuthenticator implements BiometricAuthenticator {
  _FakeAuthenticator({
    this.result = true,
    this.throws,
    this.hasHardware = true,
    this.deviceSupported = true,
    this.enrolled = const [],
  });

  final bool result;
  final String? throws;
  final bool hasHardware;
  final bool deviceSupported;
  final List<BiometricType> enrolled;

  @override
  Future<bool> canCheckBiometrics() async => hasHardware;

  @override
  Future<bool> isDeviceSupported() async => deviceSupported;

  @override
  Future<List<BiometricType>> availableBiometrics() async => enrolled;

  @override
  Future<bool> authenticate({required String localizedReason}) async {
    if (throws != null) throw PlatformException(code: throws!);
    return result;
  }
}

BiometricService _service({
  bool result = true,
  String? throws,
  bool hasHardware = true,
  bool deviceSupported = true,
  List<BiometricType> enrolled = const [],
}) => BiometricService(
  _FakeAuthenticator(
    result: result,
    throws: throws,
    hasHardware: hasHardware,
    deviceSupported: deviceSupported,
    enrolled: enrolled,
  ),
);

void main() {
  group('availability', () {
    test('a device with a passcode but no sensor still counts', () {
      // isDeviceSupported() covers PIN/pattern fallback. Requiring biometric
      // hardware would exclude a device that can perfectly well unlock a
      // stored token.
      expect(
        _service(hasHardware: false, deviceSupported: true).isAvailable(),
        completion(isTrue),
      );
    });

    test('no hardware and no passcode means unavailable', () {
      expect(
        _service(hasHardware: false, deviceSupported: false).isAvailable(),
        completion(isFalse),
      );
    });

    test('enrolled types are reported for labelling the control', () {
      expect(
        _service(enrolled: const [BiometricType.face]).enrolledTypes(),
        completion(contains(BiometricType.face)),
      );
    });
  });

  group('authenticate — each failure strands a user differently', () {
    test('a successful prompt succeeds', () async {
      final result = await _service().authenticate(reason: 'r');
      expect(result.succeeded, isTrue);
      expect(result.failure, isNull);
    });

    test('a dismissed prompt is cancelled, not unavailable', () async {
      // The distinction decides what happens next: cancelled keeps the
      // preference on and lets the user retry, unavailable turns it off.
      final result = await _service(result: false).authenticate(reason: 'r');
      expect(result.failure, BiometricFailure.cancelled);
    });

    test(
      'notEnrolled maps to unavailable so the flag can be cleared',
      () async {
        final result = await _service(throws: auth_error.notEnrolled)
            .authenticate(reason: 'r');
        expect(result.failure, BiometricFailure.unavailable);
      },
    );

    test('passcodeNotSet maps to unavailable', () async {
      final result = await _service(throws: auth_error.passcodeNotSet)
          .authenticate(reason: 'r');
      expect(result.failure, BiometricFailure.unavailable);
    });

    test('notAvailable maps to unavailable', () async {
      final result = await _service(throws: auth_error.notAvailable)
          .authenticate(reason: 'r');
      expect(result.failure, BiometricFailure.unavailable);
    });

    test('lockedOut is its own case — retrying cannot clear it', () async {
      final result = await _service(throws: auth_error.lockedOut)
          .authenticate(reason: 'r');
      expect(result.failure, BiometricFailure.lockedOut);
    });

    test('permanentlyLockedOut maps to lockedOut', () async {
      final result = await _service(throws: auth_error.permanentlyLockedOut)
          .authenticate(reason: 'r');
      expect(result.failure, BiometricFailure.lockedOut);
    });

    test('an unknown code is a dismissal, not broken hardware', () async {
      // Switching the preference off on a code we do not understand would
      // silently disable a working feature. Treating it as a dismissal keeps
      // both the prompt and the way past it.
      final result = await _service(throws: 'SomethingNew')
          .authenticate(reason: 'r');
      expect(result.failure, BiometricFailure.cancelled);
    });
  });
}
