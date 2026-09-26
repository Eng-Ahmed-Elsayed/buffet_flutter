import 'package:buffet_app/features/order/widgets/sugar_stepper.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/widgets/quantity_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _ar = lookupAppLocalizations(const Locale('ar'));
final _en = lookupAppLocalizations(const Locale('en'));

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar'), Locale('en')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('the quantity reads as "quantity, 2", not a bare number', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        QuantityStepper(
          value: 2,
          max: 5,
          onChanged: (_) {},
          moreTooltip: 'more',
          fewerTooltip: 'fewer',
          atMaxReason: 'max',
          valueLabel: _ar.quantity,
        ),
      ),
    );

    final node = tester.getSemantics(find.bySemanticsLabel(_ar.quantity));
    expect(node.value, '2');
  });

  testWidgets('a sugar button at the floor is announced as unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(_host(SugarStepper(spoons: 0, onChanged: (_) {})));

    expect(
      tester.getSemantics(find.byTooltip(_ar.removeSpoon)),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    expect(
      tester.getSemantics(find.byTooltip(_ar.addSpoon)),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: true),
    );
  });

  test('the buffet cap names the number the server set', () {
    expect(_en.buffetCapTitle(1), 'Only one drink from the buffet');
    expect(_en.buffetCapTitle(2), 'Only 2 drinks from the buffet');
    expect(_ar.buffetCapTitle(2), 'مشروبان فقط من البوفيه');
  });
}
