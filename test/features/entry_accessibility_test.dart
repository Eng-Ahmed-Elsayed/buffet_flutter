import 'dart:async';

import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/auth/change_password_screen.dart';
import 'package:buffet_app/features/auth/lock_screen.dart';
import 'package:buffet_app/features/auth/login_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/widgets/banners.dart';
import 'package:buffet_app/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_auth_controller.dart';

final _ar = lookupAppLocalizations(const Locale('ar'));
final _en = lookupAppLocalizations(const Locale('en'));

Widget _screen(
  Widget home,
  AuthState state, {
  Locale locale = const Locale('ar'),
}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(
      (r) => FakeAuthController(state, pinned: true),
    ),
  ],
  child: testApp(home: home, locale: locale),
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a password field is named by its label, and its eye toggle '
      'stays a button of its own', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _screen(
        const ChangePasswordScreen(),
        const AuthState(stage: AuthStage.signedIn),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.getSemantics(
      find.byType(TextFormField).at(1), // the new password
    );
    expect(field, isSemantics(label: _ar.newPassword, isTextField: true));

    // Merged with its label, the field swallowed the toggle: a screen reader
    // reached one node, and "Show password" was not a button on it.
    final eye = tester.getSemantics(find.byTooltip(_ar.showPassword));
    expect(eye.id, isNot(field.id));
    expect(eye, isSemantics(isButton: true, hasTapAction: true));
    handle.dispose();
  });

  testWidgets('a danger banner is announced; an info banner is not', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testApp(
        home: const Column(
          children: [
            InlineBanner(tone: BannerTone.danger, title: 'danger'),
            InlineBanner(tone: BannerTone.info, title: 'info'),
          ],
        ),
      ),
    );

    SemanticsNode node(String title) => tester.getSemantics(
      find
          .ancestor(of: find.text(title), matching: find.byType(Semantics))
          .first,
    );
    expect(node('danger'), isSemantics(isLiveRegion: true));
    expect(node('info'), isNot(isSemantics(isLiveRegion: true)));
    handle.dispose();
  });

  testWidgets('signing in shows a brand spinner that says what it is', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((r) => _SlowSignIn())],
        child: testApp(home: const LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'sara@company.com');
    await tester.enterText(fields.at(1), 'secret');
    await tester.tap(find.text(_ar.signIn));
    await tester.pump();

    // White on the disabled fill was 1.43:1.
    final spinner = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(spinner.color, BrandColors.brand);
    expect(find.bySemanticsLabel(_ar.pleaseWait), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the lock names what it does, not a sensor, and a cancelled '
      'prompt blames nobody', (tester) async {
    await tester.pumpWidget(
      _screen(
        const LockScreen(),
        const AuthState(
          stage: AuthStage.locked,
          rememberedEmail: 'sara@company.com',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_ar.unlock), findsOneWidget);
    expect(find.textContaining('البصمة'), findsNothing);
    // The fake reports a cancellation, the outcome a dismissed prompt gives.
    expect(find.text(_ar.biometricFailed), findsOneWidget);
    expect(_en.biometricFailed, isNot(contains('recognised')));
  });

  testWidgets('both sign-in labels sit as close to their fields, and Forgot? '
      'keeps a full target', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _screen(
        const LoginScreen(),
        const AuthState(stage: AuthStage.signedOut),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    double gap(String label, int field) =>
        tester.getTopLeft(fields.at(field)).dy -
        tester.getBottomLeft(find.text(label)).dy;

    expect(gap(_en.password.toUpperCase(), 1), gap(_en.email.toUpperCase(), 0));
    expect(
      tester
          .getSize(find.widgetWithText(TextButton, _en.forgotPassword))
          .height,
      greaterThanOrEqualTo(44),
    );

    // Named as written, not in the label's display capitals, with the hint
    // read after it.
    final email = tester.getSemantics(fields.at(0));
    expect(email, isSemantics(isTextField: true));
    expect(email.label, startsWith(_en.email));
    expect(email.label, isNot(contains(_en.email.toUpperCase())));
    handle.dispose();
  });
}

/// A sign-in that never answers, so the button stays in its working state.
class _SlowSignIn extends FakeAuthController {
  _SlowSignIn()
    : super(const AuthState(stage: AuthStage.signedOut), pinned: true);

  @override
  Future<void> signIn({
    required String username,
    required String password,
    required String languageCode,
    required String networkErrorFallback,
  }) => Completer<void>().future;
}
