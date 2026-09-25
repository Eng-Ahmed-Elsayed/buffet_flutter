import 'dart:convert';

import 'package:buffet_app/data/api/api_client.dart';
import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/local/biometric_enrolment_guard.dart';
import 'package:buffet_app/data/local/biometric_service.dart';
import 'package:buffet_app/data/local/preferences_store.dart';
import 'package:buffet_app/data/local/secure_token_store.dart';
import 'package:buffet_app/data/repositories/auth_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

/// Answers sign-in with a canned login response, and set-initial-password with
/// a 204. [mustChange] is what the next sign-in reports.
class _ServerAdapter implements HttpClientAdapter {
  bool mustChange = true;

  /// Refuses the next sign-in with a 400, as a server hiccup would.
  bool refuseNextLogin = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == ApiConfig.login && refuseNextLogin) {
      refuseNextLogin = false;
      return ResponseBody.fromString(
        jsonEncode({'message': 'refused'}),
        400,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.path == ApiConfig.login) {
      return ResponseBody.fromString(
        jsonEncode({
          'token': 'a-token',
          'expiresUtc': DateTime.now()
              .toUtc()
              .add(const Duration(days: 30))
              .toIso8601String(),
          'username': 'sara@buffet.test',
          'displayName': 'سارة',
          'role': 'Employee',
          'department': 'المالية',
          'mustChangePassword': mustChange,
          'canOrderForGuests': false,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

class _InertAuthenticator implements BiometricAuthenticator {
  const _InertAuthenticator();

  @override
  Future<bool> canCheckBiometrics() async => false;

  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<List<BiometricType>> availableBiometrics() async => const [];

  @override
  Future<bool> authenticate({required String localizedReason}) async => false;
}

late _ServerAdapter _server;
late AuthEvents _events;

const _prefs = PreferencesStore(FlutterSecureStorage());

/// A fresh controller over the same storage — what a cold start builds.
Future<AuthController> _launch() async {
  const storage = FlutterSecureStorage();
  _events = AuthEvents();
  final controller = AuthController(
    AuthRepository(
      dio: Dio(BaseOptions(baseUrl: 'https://example.test/api/v1'))
        ..httpClientAdapter = _server,
      tokenStore: const SecureTokenStore(storage),
      preferences: const PreferencesStore(storage),
    ),
    _events,
    const BiometricService(_InertAuthenticator()),
    const BiometricEnrolmentGuard(),
  );
  // Let the restore from storage land.
  while (controller.state.stage == AuthStage.restoring) {
    await Future<void>.delayed(Duration.zero);
  }
  return controller;
}

Future<void> _signIn(AuthController auth) => auth.signIn(
  username: 'sara@buffet.test',
  password: 'seeded',
  languageCode: 'ar',
  networkErrorFallback: 'network',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Sign-out disarms the enrolment guard over its platform channel; there is
    // no native side under test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('buffet/biometric_enrolment'),
          (call) async => null,
        );
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    _server = _ServerAdapter();
  });

  group('rule 10 — a relaunch is not a way past the forced change', () {
    test(
      'signing in on the seeded password, then relaunching, still blocks',
      () async {
        final first = await _launch();
        await _signIn(first);
        expect(first.state.stage, AuthStage.mustChangePassword);
        first.dispose();

        // The app is killed and reopened: the token works, so without the
        // stored flag this landed signed in, able to order.
        final relaunched = await _launch();
        expect(relaunched.state.stage, AuthStage.mustChangePassword);
        relaunched.dispose();
      },
    );

    test('once the password is set, a relaunch lets the user in', () async {
      final first = await _launch();
      await _signIn(first);
      _server.mustChange = false;
      await first.setInitialPassword(
        newPassword: 'a-new-password',
        languageCode: 'ar',
        networkErrorFallback: 'network',
      );
      expect(first.state.stage, AuthStage.signedIn);
      first.dispose();

      final relaunched = await _launch();
      expect(relaunched.state.stage, AuthStage.signedIn);
      relaunched.dispose();
    });

    test('an account already past the change is never blocked', () async {
      _server.mustChange = false;
      final first = await _launch();
      await _signIn(first);
      first.dispose();

      final relaunched = await _launch();
      expect(relaunched.state.stage, AuthStage.signedIn);
      relaunched.dispose();
    });

    test('signing out forgets the flag with the session', () async {
      final first = await _launch();
      await _signIn(first);
      await first.signOut();
      first.dispose();

      // The flag itself, not only the token: a flag left behind would block
      // the next person to sign in on this device.
      expect(await _prefs.readMustChangePassword(), isFalse);
      final relaunched = await _launch();
      expect(relaunched.state.stage, AuthStage.signedOut);
      relaunched.dispose();
    });

    test('set, then the re-sign-in fails: the next launch still lets them in', () async {
      final first = await _launch();
      await _signIn(first);
      _server.refuseNextLogin = true;
      await first.setInitialPassword(
        newPassword: 'a-new-password',
        languageCode: 'ar',
        networkErrorFallback: 'network',
      );
      // Through on the old token, which still works.
      expect(first.state.stage, AuthStage.signedIn);
      first.dispose();

      // The 204 released the flag, so the password they have just set does not
      // send them back to the forced screen.
      final relaunched = await _launch();
      expect(relaunched.state.stage, AuthStage.signedIn);
      relaunched.dispose();
    });
  });

  group('a 401 ends the session as completely as signing out', () {
    test('the biometric flag goes with the token', () async {
      _server.mustChange = false;
      final first = await _launch();
      await _signIn(first);
      // Switched on earlier, as enableBiometrics would after a real prompt.
      await const PreferencesStore(FlutterSecureStorage())
          .writeBiometricsEnabled(true);

      // What the interceptor does on a 401: clear the token, then signal.
      await const SecureTokenStore(FlutterSecureStorage()).clear();
      _events.signalUnauthorized();
      // The cleanup is fire-and-forget from the listener; let it finish.
      await pumpEventQueue();
      expect(first.state.stage, AuthStage.signedOut);
      expect(first.state.sessionExpired, isTrue);
      first.dispose();

      // Left behind, the flag would lock the next person to sign in on this
      // device behind the previous one's fingerprint.
      expect(
        await const PreferencesStore(FlutterSecureStorage())
            .readBiometricsEnabled(),
        isFalse,
      );
    });
  });

  group('a token that expired on the device leaves nothing behind', () {
    test('the next launch clears what the old session left', () async {
      // An expired session, as the 30-day limit leaves it: no request is ever
      // made, so no 401 runs the cleanup.
      await const SecureTokenStore(FlutterSecureStorage()).write(
        token: 'old-token',
        expiresUtc: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      );
      await _prefs.writeBiometricsEnabled(true);
      await _prefs.writeMustChangePassword(true);
      await _prefs.writeIdentity(
        role: 'Staff',
        displayName: 'سارة',
        department: 'المالية',
        canOrderForGuests: false,
      );

      final launched = await _launch();
      expect(launched.state.stage, AuthStage.signedOut);
      launched.dispose();

      // The next person to sign in inherits no fingerprint lock, no forced
      // screen and no role.
      expect(await _prefs.readBiometricsEnabled(), isFalse);
      expect(await _prefs.readMustChangePassword(), isFalse);
      expect(await _prefs.readIdentity(), isNull);
    });
  });
}
