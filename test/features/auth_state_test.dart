import 'package:buffet_app/data/models/auth_models.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:flutter_test/flutter_test.dart';

LoginResponse session({
  required bool mustChangePassword,
  String role = 'Employee',
}) => LoginResponse.fromJson({
  'token': 'a.b.c',
  'expiresUtc': '2026-09-15T08:00:00Z',
  'username': 'someone@company.com',
  'displayName': 'Someone',
  'role': role,
  'department': 'Finance',
  'mustChangePassword': mustChangePassword,
});

void main() {
  group('LoginResponse', () {
    test('reads the role from the response, not from decoding the JWT', () {
      // §4.2 is explicit: read the role from the login response. Decoding the
      // token client-side would trust something the client cannot verify.
      expect(session(mustChangePassword: false, role: 'Staff').role, 'Staff');
    });

    test('expiresUtc parses as UTC', () {
      final login = session(mustChangePassword: false);
      expect(login.expiresUtc.isUtc, isTrue);
    });

    test('mustChangePassword arrives even though the token works', () {
      // This is the trap: the token is valid, so a careless client could skip
      // the change screen and order anyway.
      final login = session(mustChangePassword: true);
      expect(login.mustChangePassword, isTrue);
      expect(login.token, isNotEmpty);
    });
  });

  group('AuthState — the §5 state machine', () {
    test('a cold start begins in restoring, not signedOut', () {
      // Showing the login screen before secure storage has been read would
      // flash it at someone who is already signed in.
      const state = AuthState.restoring();
      expect(state.stage, AuthStage.restoring);
      expect(state.session, isNull);
    });

    test('mustChangePassword is its own stage, distinct from signedIn', () {
      const state = AuthState(stage: AuthStage.mustChangePassword);
      // The router keys off this to block every other route.
      expect(state.stage, isNot(AuthStage.signedIn));
      expect(state.stage, AuthStage.mustChangePassword);
    });

    test('role decides the landing screen only once signed in', () {
      final staff = AuthState(
        stage: AuthStage.signedIn,
        session: session(mustChangePassword: false, role: 'Staff'),
      );
      expect(staff.role.startsOnQueue, isTrue);

      final employee = AuthState(
        stage: AuthStage.signedIn,
        session: session(mustChangePassword: false, role: 'Employee'),
      );
      expect(employee.role.startsOnQueue, isFalse);
    });

    test('an Admin lands on the catalogue — no admin screens exist here', () {
      final admin = AuthState(
        stage: AuthStage.signedIn,
        session: session(mustChangePassword: false, role: 'Admin'),
      );
      expect(admin.role, UserRole.admin);
      expect(admin.role.startsOnQueue, isFalse);
    });

    test('a state with no session defaults to the least-privileged role', () {
      const state = AuthState(stage: AuthStage.signedOut);
      expect(state.role, UserRole.employee);
    });

    test('the remembered email survives sign-out', () {
      // §5.1: remembering the email makes the second sign-in password-only.
      // It is not a credential.
      const state = AuthState(
        stage: AuthStage.signedOut,
        rememberedEmail: 'someone@company.com',
      );
      expect(state.rememberedEmail, 'someone@company.com');
    });
  });

  group('AuthState — the biometric lock (§6)', () {
    test('locked is a distinct stage, not a flavour of signedOut', () {
      // The router bounces every route to the lock exactly as it does for
      // mustChangePassword. Folding it into signedOut would show a login
      // screen to someone who already holds a valid token.
      const state = AuthState(stage: AuthStage.locked);
      expect(state.stage, isNot(AuthStage.signedOut));
      expect(state.stage, isNot(AuthStage.signedIn));
    });

    test('biometrics default to off, so nothing is enabled silently', () {
      // §6: never enable it without asking. A default of true would gate a
      // user behind hardware they never opted into.
      const state = AuthState(stage: AuthStage.signedIn);
      expect(state.biometricsEnabled, isFalse);
      expect(state.offerBiometricEnrolment, isFalse);
    });

    test('the enrolment offer survives copyWith until it is answered', () {
      const offered = AuthState(
        stage: AuthStage.signedIn,
        offerBiometricEnrolment: true,
      );
      // Any unrelated state change must not silently swallow the offer.
      expect(
        offered.copyWith(biometricsEnabled: true).offerBiometricEnrolment,
        isTrue,
      );
      // Answering it clears it, so the sheet cannot appear twice.
      expect(
        offered
            .copyWith(offerBiometricEnrolment: false)
            .offerBiometricEnrolment,
        isFalse,
      );
    });

    test('unlocking moves to signedIn while keeping the preference on', () {
      const locked = AuthState(
        stage: AuthStage.locked,
        biometricsEnabled: true,
      );
      final unlocked = locked.copyWith(stage: AuthStage.signedIn);

      expect(unlocked.stage, AuthStage.signedIn);
      // A successful unlock is not a reason to stop using biometrics.
      expect(unlocked.biometricsEnabled, isTrue);
    });

    test('unavailable hardware clears the flag AND lets the user through', () {
      // The strand: a flag set for hardware that can no longer satisfy a
      // prompt would leave the user at a lock with no key. §6 says fall back
      // to the password path silently and turn the flag off — here the token
      // is still valid, so they go straight in.
      const locked = AuthState(
        stage: AuthStage.locked,
        biometricsEnabled: true,
      );
      final recovered = locked.copyWith(
        stage: AuthStage.signedIn,
        biometricsEnabled: false,
      );

      expect(recovered.stage, AuthStage.signedIn);
      expect(recovered.biometricsEnabled, isFalse);
    });

    test(
      'signing out of the lock returns to signedOut with the email kept',
      () {
        // The way past the lock. The remembered email survives so the password
        // sign-in that follows is prefilled (§5.1).
        const state = AuthState(
          stage: AuthStage.signedOut,
          rememberedEmail: 'sara@company.com',
          biometricsEnabled: false,
        );
        expect(state.stage, AuthStage.signedOut);
        expect(state.rememberedEmail, 'sara@company.com');
        // The flag goes with the token it unlocked — otherwise the next user of
        // this device is gated on the previous one's fingerprint.
        expect(state.biometricsEnabled, isFalse);
      },
    );
  });
}
