import 'package:buffet_app/theme/app_theme.dart';
import 'package:buffet_app/theme/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pushes a page under the real theme and returns where its content sits one
/// frame into the transition, and where it sits once settled.
Future<(Rect, Rect)> _pushAndMeasure(
  WidgetTester tester, {
  required bool reduceMotion,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        theme: AppTheme.forLocale(const Locale('en')),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: Center(child: Text('second'))),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  final early = tester.getRect(find.text('second'));
  await tester.pumpAndSettle();
  final settled = tester.getRect(find.text('second'));
  return (early, settled);
}

void main() {
  group('§2.3 — reduced motion stops route movement', () {
    testWidgets('a pushed page is already in place under reduced motion', (
      tester,
    ) async {
      final (early, settled) = await _pushAndMeasure(
        tester,
        reduceMotion: true,
      );
      expect(early, settled);
    });

    testWidgets('and still moves when motion is allowed', (tester) async {
      // The control: proves the measurement above can see a transition at all.
      final (early, settled) = await _pushAndMeasure(
        tester,
        reduceMotion: false,
      );
      expect(early, isNot(settled));
    });
  });

  group('bottom sheets follow the same setting', () {
    testWidgets('no sheet animation under reduced motion', (tester) async {
      late AnimationStyle? style;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              style = Motion.sheet(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(style, AnimationStyle.noAnimation);
    });

    testWidgets('the framework slide otherwise', (tester) async {
      late AnimationStyle? style;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              style = Motion.sheet(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(style, isNull);
    });
  });
}
