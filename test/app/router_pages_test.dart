import 'dart:async';

import 'package:buffet_app/app/router.dart';
import 'package:buffet_app/app/routes.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_auth_controller.dart';

/// Every route in [routes], shells' branches included.
Iterable<RouteBase> _all(List<RouteBase> routes) sync* {
  for (final route in routes) {
    yield route;
    if (route is StatefulShellRoute) {
      for (final branch in route.branches) {
        yield* _all(branch.routes);
      }
    }
    yield* _all(route.routes);
  }
}

class _Screen extends StatelessWidget {
  const _Screen(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

void main() {
  // go_router 14 recognises only package:flutter's MaterialApp. Under
  // material_ui's it falls back to NoTransitionPage for a `builder:` route,
  // which silently removed every transition and the iOS edge swipe back.
  testWidgets('every app route builds its own Material page', (tester) async {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          (ref) =>
              FakeAuthController(const AuthState(stage: AuthStage.signedOut)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    final routes = _all(router.configuration.routes).toList();
    expect(routes, isNotEmpty);
    for (final route in routes) {
      switch (route) {
        case GoRoute():
          expect(route.builder, isNull, reason: route.path);
          expect(route.pageBuilder, isNotNull, reason: route.path);
        case StatefulShellRoute():
          expect(route.pageBuilder, isNotNull);
        default:
          fail('Unexpected route type ${route.runtimeType}');
      }
    }
  });

  testWidgets('a materialPage route animates as a Material page route', (
    tester,
  ) async {
    // Built inside the test, never at file load (CLAUDE.md).
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (c, s) => materialPage(s, const _Screen('one')),
        ),
        GoRoute(
          path: '/two',
          pageBuilder: (c, s) => materialPage(s, const _Screen('two')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    unawaited(router.push('/two'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final route = ModalRoute.of(tester.element(find.text('two')));
    // MaterialPage's own route: themed transitions, unlike NoTransitionPage.
    expect(route, isA<MaterialRouteTransitionMixin<void>>());
    expect(route!.transitionDuration, greaterThan(Duration.zero));
    // Mid-transition: the page beneath is still on screen.
    expect(find.text('one'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets('an unknown address shows the localised not-found screen as a '
        'Material page (${locale.languageCode})', (tester) async {
      final l10n = lookupAppLocalizations(locale);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            (ref) =>
                FakeAuthController(const AuthState(stage: AuthStage.signedOut)),
          ),
        ],
      );
      addTearDown(container.dispose);
      // The production error page, on a router with one known route, so
      // the test does not stand up a signed-in Home.
      final errorPageBuilder = container
          .read(routerProvider)
          .routerDelegate
          .builder
          .errorPageBuilder;
      expect(errorPageBuilder, isNotNull);

      final router = GoRouter(
        initialLocation: Routes.home,
        errorPageBuilder: errorPageBuilder,
        routes: [
          GoRoute(
            path: Routes.home,
            pageBuilder: (c, s) => materialPage(s, const _Screen('one')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          locale: locale,
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
        ),
      );
      await tester.pumpAndSettle();

      router.go('/no-such-place');
      await tester.pumpAndSettle();

      expect(find.text(l10n.pageNotFoundBody), findsOneWidget);
      expect(find.text(l10n.backToStart), findsOneWidget);
      final route = ModalRoute.of(
        tester.element(find.text(l10n.pageNotFoundBody)),
      );
      expect(route, isA<MaterialRouteTransitionMixin<void>>());

      // The way out goes Home.
      await tester.tap(find.text(l10n.backToStart));
      await tester.pumpAndSettle();
      expect(find.text('one'), findsOneWidget);
    });
  }
}
