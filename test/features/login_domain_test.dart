import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/auth/login_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_auth_controller.dart';

/// §5.1: the domain is shared, so sign-in asks only for the name before it.
class _RecordingSignIn extends FakeAuthController {
  _RecordingSignIn()
    : super(const AuthState(stage: AuthStage.signedOut), pinned: true);

  String? username;

  @override
  Future<void> signIn({
    required String username,
    required String password,
    required String languageCode,
    required String networkErrorFallback,
  }) async => this.username = username;
}

void main() {
  setUpAll(loadAppFonts);

  test('a name alone gets the domain; a full address is sent as typed', () {
    expect(ApiConfig.username(' sara '), 'sara@defi.com.eg');
    expect(ApiConfig.username('staff@company.com'), 'staff@company.com');
  });

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final l10n = lookupAppLocalizations(locale);

    Future<_RecordingSignIn> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = _RecordingSignIn();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith((r) => auth)],
          child: testApp(home: const LoginScreen(), locale: locale),
        ),
      );
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('${locale.languageCode}: typing a name signs in with the '
        'work address, and shows the domain on its right', (tester) async {
      final auth = await pump(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'sara');
      await tester.enterText(fields.at(1), 'secret');
      await tester.pump();

      // An address reads left to right in either language, so the domain
      // sits right of the name in Arabic too.
      final domain = find.textContaining(ApiConfig.emailDomain);
      expect(domain, findsOneWidget);
      expect(
        tester.getCenter(domain).dx,
        greaterThan(tester.getCenter(fields.at(0)).dx),
      );

      await tester.tap(find.text(l10n.signIn));
      await tester.pumpAndSettle();
      expect(auth.username, 'sara@defi.com.eg');
    });

    testWidgets('${locale.languageCode}: a full address hides the domain and '
        'goes as typed', (tester) async {
      final auth = await pump(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'staff@company.com');
      await tester.enterText(fields.at(1), 'secret');
      await tester.pump();

      expect(find.textContaining(ApiConfig.emailDomain), findsNothing);
      await tester.tap(find.text(l10n.signIn));
      await tester.pumpAndSettle();
      expect(auth.username, 'staff@company.com');
    });
  }
}
