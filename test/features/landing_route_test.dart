import 'package:buffet_app/app/router.dart';
import 'package:buffet_app/app/routes.dart';
import 'package:buffet_app/data/models/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The signed-in landing rule, tested through the function the router itself
/// calls. This file used to hold a copy of the rule, which would have kept
/// passing while the real one drifted.
String? redirectFor({required UserRole role, required String location}) =>
    signedInRedirect(role: role, location: location);

void main() {
  group('each role has exactly one landing screen', () {
    test('an employee lands on the Home tab, not the drink picker', () {
      // The composer used to be the landing screen, which is why the app
      // opened on a question ("which drink?") rather than an answer to
      // "what can I do?".
      expect(
        redirectFor(role: UserRole.employee, location: Routes.login),
        Routes.home,
      );
    });

    test('an admin lands on Home too', () {
      // There are deliberately no admin screens in this app (§5); admin work
      // stays on the web, so an admin gets the ordinary employee view.
      expect(
        redirectFor(role: UserRole.admin, location: Routes.login),
        Routes.home,
      );
    });

    test('a staff member lands on the queue', () {
      expect(
        redirectFor(role: UserRole.staff, location: Routes.login),
        Routes.queue,
      );
    });

    test('the landing holds after an unlock and a forced password change', () {
      for (final from in [Routes.lock, Routes.changePassword, Routes.splash]) {
        expect(
          redirectFor(role: UserRole.employee, location: from),
          Routes.home,
        );
        expect(redirectFor(role: UserRole.staff, location: from), Routes.queue);
      }
    });
  });

  group('a deep link cannot put a role on the wrong landing screen', () {
    test('an employee deep-linking the queue is sent Home', () {
      // Every call on that screen would 403.
      expect(
        redirectFor(role: UserRole.employee, location: Routes.queue),
        Routes.home,
      );
    });

    test('a staff member is bounced off every tab of the employee shell', () {
      // The mirror of the rule above: one landing per role is what keeps the
      // exit confirmation unambiguous about which screen closes the app.
      for (final tab in Routes.shellTabs) {
        expect(
          redirectFor(role: UserRole.staff, location: tab),
          Routes.queue,
          reason: 'staff should not reach $tab',
        );
      }
    });

    test('employees and admins reach every tab', () {
      for (final role in [UserRole.employee, UserRole.admin]) {
        for (final tab in Routes.shellTabs) {
          expect(redirectFor(role: role, location: tab), isNull);
        }
      }
    });

    test('the pushed screens are left alone for both roles', () {
      for (final role in UserRole.values) {
        for (final location in [
          Routes.catalogue,
          Routes.favouritesList,
          Routes.materials,
          Routes.notifications,
          Routes.settings,
          Routes.password,
          Routes.orderStatusFor(41),
        ]) {
          expect(
            redirectFor(role: role, location: location),
            isNull,
            reason: '$role should pass through $location',
          );
        }
      }
    });
  });

  group('signed out: the explainer once, then sign-in', () {
    test('a first launch sees the explainer, from wherever it starts', () {
      for (final from in [Routes.splash, Routes.login, Routes.home]) {
        expect(
          signedOutRedirect(onboardingSeen: false, location: from),
          Routes.onboarding,
        );
      }
    });

    test('someone who has used the app goes to sign-in, flag or not', () {
      // Seen on the emulator: a session that expired before the flag existed
      // put three slides in front of the "session expired" sign-in.
      for (final seen in [null, false, true]) {
        expect(
          signedOutRedirect(
            onboardingSeen: seen,
            location: Routes.splash,
            hasUsedApp: true,
          ),
          Routes.login,
        );
      }
    });

    test('once seen, it is sign-in, and the explainer cannot be reached', () {
      expect(
        signedOutRedirect(onboardingSeen: true, location: Routes.onboarding),
        Routes.login,
      );
      expect(
        signedOutRedirect(onboardingSeen: true, location: Routes.login),
        isNull,
      );
    });

    test('while the flag is still being read, it holds on the splash', () {
      // Otherwise someone who has seen the explainer would glimpse it on a
      // cold start before the flag arrived.
      expect(
        signedOutRedirect(onboardingSeen: null, location: Routes.login),
        Routes.splash,
      );
      expect(
        signedOutRedirect(onboardingSeen: null, location: Routes.splash),
        isNull,
      );
    });

    test('a signed-in user is moved off the explainer like off login', () {
      expect(
        redirectFor(role: UserRole.employee, location: Routes.onboarding),
        Routes.home,
      );
      expect(
        redirectFor(role: UserRole.staff, location: Routes.onboarding),
        Routes.queue,
      );
    });
  });
}
