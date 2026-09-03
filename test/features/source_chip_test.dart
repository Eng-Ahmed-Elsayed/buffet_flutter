import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/widgets/source_chip.dart';
import 'package:buffet_app/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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

BoxDecoration decorationOf(WidgetTester tester) =>
    tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.byType(SourceChip),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration!
        as BoxDecoration;

void main() {
  group('SourceChip — violet means "from my own jar"', () {
    testWidgets('a named owner renders in accent violet', (tester) async {
      await tester.pumpWidget(
        wrap(const SourceChip(label: 'المشروب', ownerName: 'أحمد حسن')),
      );

      final decoration = decorationOf(tester);
      expect(decoration.color, BrandColors.accentSurface);
      expect((decoration.border! as Border).top.color, BrandColors.accent);
    });

    testWidgets('an EMPTY owner name means company stock and is NOT violet', (
      tester,
    ) async {
      // The empty string is how the API says "the buffet's own stock".
      // Rendering that in violet would destroy the signal entirely.
      await tester.pumpWidget(
        wrap(const SourceChip(label: 'المشروب', ownerName: '')),
      );

      final decoration = decorationOf(tester);
      expect(decoration.color, BrandColors.page);
      expect((decoration.border! as Border).top.color, BrandColors.brandLight);
    });

    testWidgets('whitespace-only owner is treated as company stock', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const SourceChip(label: 'المشروب', ownerName: '   ')),
      );
      expect(decorationOf(tester).color, BrandColors.page);
    });

    testWidgets('names the owner so staff know which jar to reach for', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const SourceChip(label: 'المشروب', ownerName: 'أحمد حسن')),
      );

      // The owner's name is present, bidi-isolated inside the label.
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(SourceChip),
          matching: find.byType(Text),
        ),
      );
      expect(text.data, contains('أحمد حسن'));
      // The colon is the punctuation half of the "from my own jar" signal.
      expect(text.data, startsWith('المشروب: '));
    });

    testWidgets('company stock shows the bare label — no colon, no source', (
      tester,
    ) async {
      // Naming the buffet on every chip is noise: it is where a drink comes
      // from unless something says otherwise. Only a personal jar earns the
      // "label: source" form.
      await tester.pumpWidget(
        wrap(const SourceChip(label: 'المشروب', ownerName: '')),
      );

      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(SourceChip),
          matching: find.byType(Text),
        ),
      );
      expect(text.data, 'المشروب');
      expect(text.data, isNot(contains(':')));
    });

    testWidgets('and in English too', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SourceChip(label: 'Drink', ownerName: ''),
          locale: const Locale('en'),
        ),
      );

      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(SourceChip),
          matching: find.byType(Text),
        ),
      );
      expect(text.data, 'Drink');
    });
  });

  group('layout direction', () {
    testWidgets('the app renders RTL under the Arabic locale', (tester) async {
      await tester.pumpWidget(
        wrap(const SourceChip(label: 'المشروب', ownerName: '')),
      );

      final direction = Directionality.of(
        tester.element(find.byType(SourceChip)),
      );
      expect(direction, TextDirection.rtl);
    });

    testWidgets('and LTR under English', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SourceChip(label: 'Drink', ownerName: ''),
          locale: const Locale('en'),
        ),
      );

      final direction = Directionality.of(
        tester.element(find.byType(SourceChip)),
      );
      expect(direction, TextDirection.ltr);
    });
  });
}
