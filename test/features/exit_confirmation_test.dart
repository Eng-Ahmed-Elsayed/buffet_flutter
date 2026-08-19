import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/widgets/exit_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap({Locale locale = const Locale('ar')}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('ar'), Locale('en')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: const ExitConfirmation(child: Scaffold(body: Text('landing'))),
);

/// The PopScope the widget builds.
///
/// Walked out of the tree rather than found by type argument: PopScope is
/// generic and its argument is inferred, so `find.byType` with a guessed
/// parameter matches nothing.
PopScope<dynamic> popScopeOf(WidgetTester tester) =>
    tester.allWidgets.whereType<PopScope<dynamic>>().first;

/// Fires the system back gesture the way the platform does.
Future<void> pressBack(WidgetTester tester) async {
  popScopeOf(tester).onPopInvokedWithResult!(false, null);
  await tester.pumpAndSettle();
}

void main() {
  group('ExitConfirmation — back on a landing screen', () {
    testWidgets('never pops on its own', (tester) async {
      await tester.pumpWidget(wrap());

      // canPop false is the whole mechanism: the callback decides, so the
      // confirmation can be shown before anything closes.
      expect(popScopeOf(tester).canPop, isFalse);
    });

    testWidgets('asks before closing rather than closing', (tester) async {
      await tester.pumpWidget(wrap());
      await pressBack(tester);

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(find.text(l10n.exitAppTitle), findsOneWidget);
      // Still there — asking closed nothing.
      expect(find.text('landing'), findsOneWidget);
    });

    testWidgets('dismissing keeps the user on the screen', (tester) async {
      await tester.pumpWidget(wrap());
      await pressBack(tester);

      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      expect(find.text(l10n.exitAppTitle), findsNothing);
      expect(find.text('landing'), findsOneWidget);
    });

    testWidgets('renders in English too', (tester) async {
      await tester.pumpWidget(wrap(locale: const Locale('en')));
      await pressBack(tester);

      // Both locales carry the strings — this is not an Arabic-only screen.
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.exitAppTitle), findsOneWidget);
    });
  });
}
