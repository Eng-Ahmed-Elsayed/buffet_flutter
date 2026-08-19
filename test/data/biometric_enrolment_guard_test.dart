import 'package:buffet_app/data/local/biometric_enrolment_guard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('buffet/biometric_enrolment');
  final calls = <String>[];
  String? reply;
  Object? throwThis;

  setUp(() {
    calls.clear();
    reply = 'VALID';
    throwThis = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (throwThis != null) throw throwThis!;
          return call.method == 'arm' ? true : reply;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('on Android — the platform that can answer', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

    test('VALID means enrolment is unchanged', () async {
      reply = 'VALID';
      expect(
        await const BiometricEnrolmentGuard().check(),
        EnrolmentState.valid,
      );
    });

    test('CHANGED is the signal that clears the token', () async {
      // §6: a changed enrolment is untrusted. A colleague who added their own
      // fingerprint must not inherit the session.
      reply = 'CHANGED';
      expect(
        await const BiometricEnrolmentGuard().check(),
        EnrolmentState.changed,
      );
    });

    test('an unrecognised reply is unavailable, never changed', () async {
      // Signing users out because a device answered unusually would be worse
      // than the risk being guarded against.
      reply = 'SOMETHING_ELSE';
      expect(
        await const BiometricEnrolmentGuard().check(),
        EnrolmentState.unavailable,
      );
    });

    test('a platform failure is unavailable, never changed', () async {
      throwThis = PlatformException(code: 'KEYSTORE_FAILURE');
      expect(
        await const BiometricEnrolmentGuard().check(),
        EnrolmentState.unavailable,
      );
    });

    test('a missing host implementation does not crash', () async {
      throwThis = MissingPluginException();
      expect(
        await const BiometricEnrolmentGuard().check(),
        EnrolmentState.unavailable,
      );
    });

    test('arm and disarm reach the host', () async {
      const guard = BiometricEnrolmentGuard();
      await guard.arm();
      await guard.disarm();
      expect(calls, ['arm', 'disarm']);
    });

    test('arm survives a device with no secure lock screen', () async {
      throwThis = PlatformException(code: 'NO_SECURE_LOCK');
      // Must not throw: the protection is simply unavailable there.
      await expectLater(const BiometricEnrolmentGuard().arm(), completes);
    });
  });

  group('on iOS — deliberately not wired', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('reports unavailable without calling the host at all', () async {
      expect(
        await const BiometricEnrolmentGuard().check(),
        EnrolmentState.unavailable,
      );
      // No channel traffic: the guard short-circuits on platform.
      expect(calls, isEmpty);
    });

    test('arm and disarm are no-ops rather than errors', () async {
      const guard = BiometricEnrolmentGuard();
      await guard.arm();
      await guard.disarm();
      expect(calls, isEmpty);
    });
  });
}
