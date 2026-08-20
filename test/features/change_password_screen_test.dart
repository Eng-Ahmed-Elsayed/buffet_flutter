import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/auth/change_password_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
