import 'package:buffet_app/data/api/api_client.dart';
import 'package:buffet_app/data/local/biometric_enrolment_guard.dart';
import 'package:buffet_app/data/local/biometric_service.dart';
import 'package:buffet_app/data/local/preferences_store.dart';
import 'package:buffet_app/data/local/secure_token_store.dart';
import 'package:buffet_app/data/repositories/auth_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/auth/change_password_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

Widget _app(AuthStage stage) => ProviderScope(
  overrides: [authStageProvider.overrideWith((ref) => stage)],
  child: const MaterialApp(
    locale: Locale('ar'),
    supportedLocales: [Locale('ar'), Locale('en')],
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: ChangePasswordScreen(),
  ),
);

void main() {
  group('§5.2 — the current-password field follows how the user got here', () {
    testWidgets('hidden on the forced first-run path', (tester) async {
      await tester.pumpWidget(_app(AuthStage.mustChangePassword));
      await tester.pumpAndSettle();

      // The user proved this password by signing in seconds ago. Asking again
      // is friction with no security value, and it lands hardest on the people
      // onboarding from a default handed to them on a slip of paper.
      expect(find.text('كلمة المرور الحالية'), findsNothing);
      expect(find.text('كلمة المرور الجديدة'), findsOneWidget);
    });

    testWidgets('shown on the voluntary path from settings', (tester) async {
      await tester.pumpWidget(_app(AuthStage.signedIn));
      await tester.pumpAndSettle();

      expect(find.text('كلمة المرور الحالية'), findsOneWidget);
    });
  });

  group('the new password states its rule, and keeps stating it', () {
    testWidgets('a short password shows "at least 8 characters" as the error', (
      tester,
    ) async {
      await tester.pumpWidget(_app(AuthStage.mustChangePassword));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'abc');
      await tester.enterText(fields.at(1), 'abc');
      await tester.tap(find.text('حفظ ومتابعة'));
      await tester.pumpAndSettle();

      // An error replaces the helper text. An empty error made the rule
      // vanish at the very moment it was broken; now the rule IS the error.
      expect(find.text('٨ أحرف على الأقل'), findsOneWidget);
    });
  });

  group('the forced screen still cannot be dismissed', () {
    testWidgets('back is blocked and no back arrow is drawn', (tester) async {
      await tester.pumpWidget(_app(AuthStage.mustChangePassword));
      await tester.pumpAndSettle();

      // The token already works, so a client that let the user past would let
      // them order on the shared seeded password (rule 10).
      final popScope = tester.allWidgets.whereType<PopScope<dynamic>>().first;
      expect(popScope.canPop, isFalse);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('the voluntary screen pops normally', (tester) async {
      await tester.pumpWidget(_app(AuthStage.signedIn));
      await tester.pumpAndSettle();

      final popScope = tester.allWidgets.whereType<PopScope<dynamic>>().first;
      expect(popScope.canPop, isTrue);
    });
  });

  group('the voluntary change, from the account', () {
    testWidgets('says it worked and goes back', (tester) async {
      final auth = _AcceptingAuthController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStageProvider.overrideWith((ref) => AuthStage.signedIn),
            authControllerProvider.overrideWith((ref) => auth),
          ],
          child: const _RoutedPassword(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'old-password');
      await tester.enterText(fields.at(1), 'a-new-password');
      await tester.enterText(fields.at(2), 'a-new-password');
      // Plain "save": there is nowhere further to continue to.
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();

      expect(auth.changed, isTrue);
      // Back on the account, with the outcome said — not a filled form left
      // sitting there with no sign that anything happened.
      expect(find.byType(ChangePasswordScreen), findsNothing);
      expect(find.text('تم تغيير كلمة المرور'), findsOneWidget);
    });
  });

  group('the forced screen has one way out', () {
    testWidgets('signing out, which ends the session with the block', (
      tester,
    ) async {
      final auth = _AcceptingAuthController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStageProvider.overrideWith(
              (ref) => AuthStage.mustChangePassword,
            ),
            authControllerProvider.overrideWith((ref) => auth),
          ],
          child: const MaterialApp(
            locale: Locale('ar'),
            supportedLocales: [Locale('ar'), Locale('en')],
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: ChangePasswordScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      await tester.tap(find.text(l10n.signOut));
      await tester.pumpAndSettle();

      expect(auth.signedOut, isTrue);
    });

    testWidgets('the voluntary screen offers no sign-out', (tester) async {
      await tester.pumpWidget(_app(AuthStage.signedIn));
      await tester.pumpAndSettle();

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(find.text(l10n.signOut), findsNothing);
    });
  });
}

/// The account, with the voluntary change pushed above it. The router is built
/// in initState, never at file load (CLAUDE.md).
class _RoutedPassword extends StatefulWidget {
  const _RoutedPassword();

  @override
  State<_RoutedPassword> createState() => _RoutedPasswordState();
}

class _RoutedPasswordState extends State<_RoutedPassword> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/password'),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: '/password',
          builder: (context, state) => const ChangePasswordScreen(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routerConfig: _router,
  );
}

/// Accepts any voluntary change, as a 204 would, without the network.
class _AcceptingAuthController extends AuthController {
  _AcceptingAuthController()
    : super(
        AuthRepository(
          dio: Dio(),
          tokenStore: const SecureTokenStore(FlutterSecureStorage()),
          preferences: const PreferencesStore(FlutterSecureStorage()),
        ),
        AuthEvents(),
        const BiometricService(_InertAuthenticator()),
        const BiometricEnrolmentGuard(),
      ) {
    state = const AuthState(stage: AuthStage.signedIn);
  }

  bool changed = false;
  bool signedOut = false;

  @override
  Future<void> signOut() async {
    signedOut = true;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    changed = true;
  }
}

class _InertAuthenticator implements BiometricAuthenticator {
  const _InertAuthenticator();

  @override
  Future<bool> canCheckBiometrics() async => false;

  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<List<BiometricType>> availableBiometrics() async => const [];

  @override
  Future<bool> authenticate({required String localizedReason}) async => false;
}
