import 'package:buffet_app/app/locale_controller.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/auth/login_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real screen through the real [LocaleController], so a switch that
/// updates the control but not the app-wide locale would fail here.
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    return MaterialApp(
      locale: locale,
      supportedLocales: LocaleController.supported,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LoginScreen(),
    );
  }
}

Future<void> pump(WidgetTester tester) async {
  // Tall enough that the toggle, which sits below the sign-in button, is laid
  // out rather than scrolled off — this screen is a ListView.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const ProviderScope(child: _Harness()));
  await tester.pumpAndSettle();
}

Widget _appWith({required bool expired}) => ProviderScope(
  overrides: [sessionExpiredProvider.overrideWithValue(expired)],
  child: const MaterialApp(
    locale: Locale('ar'),
    supportedLocales: LocaleController.supported,
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: LoginScreen(),
  ),
);

void main() {
  group('an expired session explains itself', () {
    testWidgets('a 401-ended session says so on the login screen', (
      tester,
    ) async {
      // The token lasts 30 days and there is no refresh endpoint, so this
      // lands on somebody who did nothing wrong and was mid-task. Dropped at a
      // sign-in screen with no reason, it reads as the app losing their work.
      await tester.pumpWidget(_appWith(expired: true));
      await tester.pumpAndSettle();

      expect(find.text('انتهت الجلسة'), findsOneWidget);
    });

    testWidgets('an ordinary signed-out screen carries no such notice', (
      tester,
    ) async {
      await tester.pumpWidget(_appWith(expired: false));
      await tester.pumpAndSettle();

      expect(find.text('انتهت الجلسة'), findsNothing);
      // Anchored, so this cannot pass on a blank screen.
      expect(find.text('تسجيل الدخول'), findsWidgets);
    });
  });

  group('the language can be changed BEFORE signing in', () {
    testWidgets('the toggle is on the login screen at all', (tester) async {
      // Settings is behind the sign-in this screen gates, and the app opens in
      // Arabic regardless of the device language — so without this control an
      // English-speaking user cannot read the screen they must sign in on, and
      // has no way to fix it. That is unrecoverable, not merely annoying.
      await pump(tester);

      expect(find.byType(SegmentedButton<Locale>), findsOneWidget);
    });

    testWidgets('each language is labelled in its OWN script', (tester) async {
      // Someone who has landed in a language they cannot read still has to be
      // able to find their way out, so "English" is never rendered as
      // "الإنجليزية" and vice versa.
      await pump(tester);

      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('choosing English re-renders the screen in English', (
      tester,
    ) async {
      await pump(tester);

      // Arabic is the default, whatever the device says.
      expect(find.text('تسجيل الدخول'), findsWidgets);

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsWidgets);
      expect(find.text('تسجيل الدخول'), findsNothing);
    });

    testWidgets('the switch flips the whole screen to LTR and back', (
      tester,
    ) async {
      await pump(tester);
      expect(
        Directionality.of(tester.element(find.byType(LoginScreen))),
        TextDirection.rtl,
      );

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(LoginScreen))),
        TextDirection.ltr,
      );

      // And back — a one-way switch would strand an Arabic reader who tapped
      // the wrong segment.
      await tester.tap(find.text('العربية'));
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(LoginScreen))),
        TextDirection.rtl,
      );
    });
  });
}
