import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models/auth_models.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/change_password_screen.dart';
import '../features/auth/lock_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/home/home_screen.dart';
import '../features/materials/my_materials_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/order/composer_screen.dart';
import '../features/order/favourites_screen.dart';
import '../features/order/my_orders_screen.dart';
import '../features/order/order_mode.dart';
import '../features/order/order_status_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/staff_queue/queue_screen.dart';
import 'employee_shell.dart';
import 'not_found_screen.dart';
import 'routes.dart';

/// Where a signed-in user belongs, or null to let them through.
///
/// Public so `landing_route_test.dart` holds the real rule to account, rather
/// than a copy of it that could drift.
///
/// Each role has exactly one landing screen, and the router bounces the other
/// role off it:
/// - staff land on the queue and are bounced off every tab of the employee
///   shell;
/// - everyone else (employees and admins) lands on Home and is bounced off
///   the queue.
String? signedInRedirect({required UserRole role, required String location}) {
  // Nobody signed in belongs on the splash, login, lock or forced-change
  // screens; send them to their landing screen by role.
  if (location == Routes.splash ||
      location == Routes.onboarding ||
      location == Routes.login ||
      location == Routes.lock ||
      location == Routes.changePassword) {
    return role.startsOnQueue ? Routes.queue : Routes.home;
  }

  // The queue is staff-only. An employee reaching it by deep link goes home
  // rather than seeing a screen whose every call 403s.
  if (location == Routes.queue && !role.startsOnQueue) return Routes.home;

  // And the mirror: the shell is the EMPLOYEE's. Staff have one landing, the
  // queue, and push what they need from there — which keeps ExitConfirmation
  // unambiguous about which screen closes the app.
  if (Routes.shellTabs.contains(location) && role.startsOnQueue) {
    return Routes.queue;
  }

  return null;
}

/// Where a signed-out user belongs: the first-launch explainer once per
/// install, then sign-in. Held on the splash while the flag is still being
/// read (`onboardingSeen == null`), so someone who has seen the explainer
/// never glimpses it again.
///
/// [hasUsedApp] (a remembered email, or a session that just ended) goes to
/// sign-in whatever the flag says, read from the same auth state the redirect
/// runs on, so no frame routes a returning user to the explainer while the
/// flag catches up.
String? signedOutRedirect({
  required bool? onboardingSeen,
  required String location,
  bool hasUsedApp = false,
}) {
  final target = hasUsedApp
      ? Routes.login
      : switch (onboardingSeen) {
          null => Routes.splash,
          false => Routes.onboarding,
          true => Routes.login,
        };
  return location == target ? null : target;
}

/// Every route's page, built explicitly as `material_ui`'s [MaterialPage].
///
/// **Never go back to `builder:`.** go_router 14 picks a page type by looking
/// for `package:flutter`'s own `MaterialApp`, which the app no longer uses
/// since the move to `material_ui` (Flutter 3.50). Not finding it, it falls
/// back to `NoTransitionPage`: every route then appeared without a
/// transition, Android lost its predictive-back animation, and iOS lost the
/// edge swipe back that CLAUDE.md keeps Cupertino's transition for. This page
/// reads the theme's `PageTransitionsTheme`, so `ReducedMotionPageTransitionsBuilder`
/// and the Cupertino builder apply again. `router_pages_test.dart`.
Page<void> materialPage(GoRouterState state, Widget child) =>
    MaterialPage<void>(
      key: state.pageKey,
      name: state.name ?? state.path,
      arguments: <String, String>{
        ...state.pathParameters,
        ...state.uri.queryParameters,
      },
      restorationId: state.pageKey.value,
      child: child,
    );

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

  // The first-launch flag is read from storage alongside the session; the
  // router re-runs its redirect when either arrives or changes.
  final onboarding = ValueNotifier<bool?>(
    ref.read(onboardingControllerProvider),
  );
  ref.listen<bool?>(
    onboardingControllerProvider,
    (_, next) => onboarding.value = next,
  );
  ref.onDispose(onboarding.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: Listenable.merge([notifier, onboarding]),
    // An address the app does not have. Without this, go_router's own error
    // text appeared bare (English, no Material), for the reason [materialPage]
    // exists.
    errorPageBuilder: (context, state) =>
        materialPage(state, const NotFoundScreen()),

    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      switch (auth.stage) {
        // Still reading secure storage. Hold on the splash rather than
        // flashing the login screen at someone who is already signed in.
        case AuthStage.restoring:
          return location == Routes.splash ? null : Routes.splash;

        case AuthStage.signedOut:
          return signedOutRedirect(
            onboardingSeen: ref.read(onboardingControllerProvider),
            location: location,
            hasUsedApp: auth.rememberedEmail != null || auth.sessionExpired,
          );

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
          return signedInRedirect(role: auth.role, location: location);
      }
    },

    routes: [
      GoRoute(
        path: Routes.splash,
        pageBuilder: (context, state) =>
            materialPage(state, const SplashScreen()),
      ),
      GoRoute(
        path: Routes.onboarding,
        pageBuilder: (context, state) =>
            materialPage(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: Routes.login,
        pageBuilder: (context, state) =>
            materialPage(state, const LoginScreen()),
      ),
      GoRoute(
        path: Routes.lock,
        pageBuilder: (context, state) =>
            materialPage(state, const LockScreen()),
      ),
      GoRoute(
        path: Routes.changePassword,
        pageBuilder: (context, state) =>
            materialPage(state, const ChangePasswordScreen()),
      ),
      // The employee's four tabs. Each branch keeps its own stack and scroll
      // position; everything that is a step in a task is a top-level route
      // below, pushed on the root navigator above the bar.
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, shell) =>
            materialPage(state, EmployeeShell(shell: shell)),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                pageBuilder: (context, state) =>
                    materialPage(state, const HomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.favourites,
                pageBuilder: (context, state) =>
                    materialPage(state, const FavouritesScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.myOrders,
                pageBuilder: (context, state) =>
                    materialPage(state, const MyOrdersScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.account,
                pageBuilder: (context, state) =>
                    materialPage(state, const SettingsScreen()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.catalogue,
        // The seed carries how the composer was opened — for the user, or for
        // a guest. Absent for the staff "order for myself" push, which defaults
        // to self, and absent on any deep link, which is deliberate: mode is
        // not something a URL should be able to assert.
        pageBuilder: (context, state) => materialPage(
          state,
          ComposerScreen(
            seed: state.extra is ComposerSeed
                ? state.extra! as ComposerSeed
                : const ComposerSeed(),
          ),
        ),
      ),
      GoRoute(
        path: Routes.orderStatus,
        // A malformed id goes Home — through the redirect, so staff land on
        // the queue — rather than rendering a screen outside its shell.
        redirect: (context, state) =>
            int.tryParse(state.pathParameters['orderId'] ?? '') == null
            ? Routes.home
            : null,
        pageBuilder: (context, state) => materialPage(
          state,
          OrderStatusScreen(
            orderId: int.parse(state.pathParameters['orderId']!),
          ),
        ),
      ),
      GoRoute(
        path: Routes.favouritesList,
        // Only ever pushed from the composer, which receives the pick.
        pageBuilder: (context, state) =>
            materialPage(state, const FavouritesScreen(returnsPick: true)),
      ),
      GoRoute(
        path: Routes.materials,
        pageBuilder: (context, state) =>
            materialPage(state, const MyMaterialsScreen()),
      ),
      GoRoute(
        path: Routes.queue,
        pageBuilder: (context, state) =>
            materialPage(state, const QueueScreen()),
      ),
      GoRoute(
        path: Routes.notifications,
        pageBuilder: (context, state) =>
            materialPage(state, const NotificationsScreen()),
      ),
      GoRoute(
        path: Routes.settings,
        pageBuilder: (context, state) =>
            materialPage(state, const SettingsScreen()),
      ),
      // The same screen as the forced change: it reads the auth stage and,
      // signed in, asks for the current password and pops when done.
      GoRoute(
        path: Routes.password,
        pageBuilder: (context, state) =>
            materialPage(state, const ChangePasswordScreen()),
      ),
    ],
  );
});
