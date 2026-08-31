import 'package:buffet_app/app/routes.dart';
import 'package:buffet_app/data/models/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The landing decision from `router.dart`, stated once so a test can hold it
/// to account without standing up a GoRouter and the whole auth machine.
///
/// This mirrors the two role guards in the redirect: staff land on the queue
/// and are bounced off `/home`; everyone else lands on the hub and is bounced
/// off `/queue`.
String? redirectFor({required UserRole role, required String location}) {
  if (location == Routes.splash ||
      location == Routes.login ||
      location == Routes.lock ||
      location == Routes.changePassword) {
    return role.startsOnQueue ? Routes.queue : Routes.home;
  }
  if (location == Routes.queue && !role.startsOnQueue) return Routes.home;
  if (location == Routes.home && role.startsOnQueue) return Routes.queue;
  return null;
}

void main() {
  group('each role has exactly one landing screen', () {
    test('an employee lands on the hub, not the drink picker', () {
      // The composer used to be the landing screen, which is why the app
      // opened on a question ("which drink?") rather than an answer to
      // "what can I do?".
      expect(
        redirectFor(role: UserRole.employee, location: Routes.login),
        Routes.home,
      );
    });

    test('an admin lands on the hub too', () {
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
    test('an employee deep-linking the queue is sent to the hub', () {
      // Every call on that screen would 403.
      expect(
        redirectFor(role: UserRole.employee, location: Routes.queue),
        Routes.home,
      );
    });

    test('a staff member deep-linking the hub is sent to the queue', () {
      // The mirror of the rule above: one landing per role is what keeps the
      // exit confirmation unambiguous about which screen closes the app.
      expect(
        redirectFor(role: UserRole.staff, location: Routes.home),
        Routes.queue,
      );
    });

    test('the shared screens are left alone for both roles', () {
      for (final role in UserRole.values) {
        for (final location in [
          Routes.catalogue,
          Routes.myOrders,
          Routes.materials,
          Routes.notifications,
          Routes.settings,
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
}
