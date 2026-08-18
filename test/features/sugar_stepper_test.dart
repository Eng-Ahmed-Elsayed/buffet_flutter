import 'package:buffet_app/features/order/widgets/sugar_stepper.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a widget in the same localisation and directionality the app uses.
Widget wrap(Widget child, {Locale locale = const Locale('ar')}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('ar'), Locale('en')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);

void main() {
  group('SugarStepper', () {
    testWidgets('renders zero as an explicit "no sugar", not a blank', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(SugarStepper(spoons: 0, onChanged: (_) {})));

      // The count itself is shown...
      expect(find.text('0'), findsOneWidget);
      // ...and labelled as a deliberate choice rather than an empty field.
      expect(find.text('بدون سكر'), findsOneWidget);
    });

    testWidgets('the decrement button is disabled only at the floor', (
      tester,
    ) async {
      var value = 0;
      await tester.pumpWidget(
        wrap(SugarStepper(spoons: 0, onChanged: (v) => value = v)),
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      // Nothing fired — it cannot go below zero.
      expect(value, 0);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(value, 1);
    });

    testWidgets('increments and decrements through the callback', (
      tester,
    ) async {
      var value = 2;
      await tester.pumpWidget(
        wrap(SugarStepper(spoons: 2, onChanged: (v) => value = v)),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(value, 3);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      expect(value, 1);
    });

    testWidgets('both targets meet the 44px minimum', (tester) async {
      await tester.pumpWidget(wrap(SugarStepper(spoons: 1, onChanged: (_) {})));

      for (final icon in [Icons.add, Icons.remove]) {
        final size = tester.getSize(
          find
              .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
              .first,
        );
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('renders in English too', (tester) async {
      await tester.pumpWidget(
        wrap(
          SugarStepper(spoons: 0, onChanged: (_) {}),
          locale: const Locale('en'),
        ),
      );

      expect(find.text('No sugar'), findsOneWidget);
    });
  });
}
