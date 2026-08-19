import 'package:buffet_app/features/settings/settings_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap({Locale locale = const Locale('ar')}) => ProviderScope(
  child: MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const SettingsScreen(),
  ),
);

void main() {
  group('SettingsScreen — the language switch', () {
    testWidgets('offers both supported locales', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      expect(find.byType(RadioListTile<Locale>), findsNWidgets(2));
    });

    testWidgets('labels each language in its OWN script, in both locales', (
      tester,
    ) async {
      // Someone who switched to a language they cannot read has to be able
      // to find their way back, so "English" is never translated to
      // "الإنجليزية" and vice versa.
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      await tester.pumpWidget(wrap(locale: const Locale('en')));
      await tester.pump();
      expect(find.text('العربية'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('renders RTL in Arabic and LTR in English', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(
        Directionality.of(tester.element(find.byType(SettingsScreen))),
        TextDirection.rtl,
      );

      await tester.pumpWidget(wrap(locale: const Locale('en')));
      await tester.pump();
      expect(
        Directionality.of(tester.element(find.byType(SettingsScreen))),
        TextDirection.ltr,
      );
    });

    testWidgets('offers sign-out', (tester) async {
      await tester.pumpWidget(wrap(locale: const Locale('en')));
      await tester.pump();
      expect(find.text('Sign out'), findsOneWidget);
    });
  });
}
