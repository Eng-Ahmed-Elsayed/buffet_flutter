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
}
