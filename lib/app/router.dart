import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/change_password_screen.dart';
import '../features/auth/lock_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/home/home_screen.dart';
import '../features/materials/my_materials_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/order/composer_screen.dart';
import '../features/order/my_orders_screen.dart';
import '../features/order/order_mode.dart';
import '../features/order/order_status_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/staff_queue/queue_screen.dart';
import 'routes.dart';

/// Implements the §5 auth state machine as a redirect guard.
///
/// All four decisions live here rather than in the screens, because a screen
/// that guards itself can be reached by a route that forgot to.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref.listen<AuthState>(
    authControllerProvider,
    (_, next) => notifier.value = next,
  );
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: notifier,

    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      switch (auth.stage) {
        // Still reading secure storage. Hold on the splash rather than
        // flashing the login screen at someone who is already signed in.
        case AuthStage.restoring:
          return location == Routes.splash ? null : Routes.splash;

        case AuthStage.signedOut:
          return location == Routes.login ? null : Routes.login;

        // A stored token exists but nothing is revealed until the prompt
        // succeeds. Every route bounces here, exactly as mustChangePassword
        // does — a deep link must not walk around the gate.
        case AuthStage.locked:
          return location == Routes.lock ? null : Routes.lock;

        // The token works here, so every route must bounce back to the change
        // screen — otherwise a deep link would let someone order on the shared
        // seeded password (§5, rule 10).
        case AuthStage.mustChangePassword:
          return location == Routes.changePassword
              ? null
              : Routes.changePassword;

        case AuthStage.signedIn:
          // Nobody signed in belongs on the splash, login or forced-change
          // screens; send them to their landing screen by role.
          if (location == Routes.splash ||
              location == Routes.login ||
              location == Routes.lock ||
              location == Routes.changePassword) {
            return auth.role.startsOnQueue ? Routes.queue : Routes.home;
          }

          // The queue is staff-only. An employee reaching it by deep link goes
          // to the hub rather than seeing a screen whose every call 403s.
          if (location == Routes.queue && !auth.role.startsOnQueue) {
            return Routes.home;
          }

          // And the mirror of it: /home is the EMPLOYEE landing screen. Staff
          // have one landing, the queue, and reach the composer by pushing it
          // from there — which is what keeps ExitConfirmation unambiguous about
          // which screen closes the app.
          if (location == Routes.home && auth.role.startsOnQueue) {
            return Routes.queue;
          }

          return null;
      }
    },

    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.lock,
        builder: (context, state) => const LockScreen(),
      ),
      GoRoute(
        path: Routes.changePassword,
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.catalogue,
        // The seed carries how the composer was opened — for the user, or for
        // a guest. Absent for the staff "order for myself" push, which defaults
        // to self, and absent on any deep link, which is deliberate: mode is
        // not something a URL should be able to assert.
        builder: (context, state) => ComposerScreen(
          seed: state.extra is ComposerSeed
              ? state.extra! as ComposerSeed
              : const ComposerSeed(),
        ),
      ),
      GoRoute(
        path: Routes.orderStatus,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['orderId'] ?? '');
          if (id == null) return const HomeScreen();
          return OrderStatusScreen(orderId: id);
        },
      ),
      GoRoute(
        path: Routes.myOrders,
        builder: (context, state) => const MyOrdersScreen(),
      ),
      GoRoute(
        path: Routes.materials,
        builder: (context, state) => const MyMaterialsScreen(),
      ),
      GoRoute(
        path: Routes.queue,
        builder: (context, state) => const QueueScreen(),
      ),
      GoRoute(
        path: Routes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});
