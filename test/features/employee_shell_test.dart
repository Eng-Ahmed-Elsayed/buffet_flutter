import 'package:buffet_app/app/employee_shell.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The shell's back behaviour, driven through the real system back path
/// (`handlePopRoute` → go_router's delegate), not by calling a PopScope.
///
/// That path is the point. go_router only asks a tab's own navigator when it
/// can pop; a tab ROOT cannot, so the gesture goes straight to the shell page.
/// A guard placed on a tab's screen would never be asked, and the app would
/// simply close. Only a test through the real path can tell those apart.
Widget _app({required Future<void> Function() onExit}) {
  Widget tab(String name) => Scaffold(body: Center(child: Text(name)));

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            EmployeeShell(shell: shell, onExit: onExit),
        branches: [
          for (final name in ['home', 'favourites', 'orders', 'account'])
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/$name', builder: (c, s) => tab('$name body')),
              ],
            ),
        ],
      ),
      GoRoute(path: '/pushed', builder: (c, s) => tab('pushed body')),
    ],
  );

  return MaterialApp.router(
    locale: const Locale('en'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    routerConfig: router,
  );
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('the four tabs are named, and Home is where it starts', (
    tester,
  ) async {
    await tester.pumpWidget(_app(onExit: () async {}));
    await tester.pumpAndSettle();

    expect(find.text('home body'), findsOneWidget);
    for (final label in [
      l10n.navHome,
      l10n.navFavourites,
      l10n.navOrders,
      l10n.navAccount,
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('a tab is one tap away', (tester) async {
    await tester.pumpWidget(_app(onExit: () async {}));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.navOrders));
    await tester.pumpAndSettle();

    expect(find.text('orders body'), findsOneWidget);
  });

  testWidgets('back from another tab returns Home, and asks nothing', (
    tester,
  ) async {
    var exited = false;
    await tester.pumpWidget(_app(onExit: () async => exited = true));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.navAccount));
    await tester.pumpAndSettle();
    expect(find.text('account body'), findsOneWidget);

    await _back(tester);

    expect(find.text('home body'), findsOneWidget);
    expect(find.text(l10n.exitAppTitle), findsNothing);
    expect(exited, isFalse);
  });

  testWidgets('back on Home asks before closing, and closes on confirm', (
    tester,
  ) async {
    var exited = false;
    await tester.pumpWidget(_app(onExit: () async => exited = true));
    await tester.pumpAndSettle();

    await _back(tester);
    expect(find.text(l10n.exitAppTitle), findsOneWidget);
    expect(exited, isFalse);

    await tester.tap(find.text(l10n.exitAppConfirm));
    await tester.pumpAndSettle();
    expect(exited, isTrue);
  });

  testWidgets('dismissing the question keeps the user Home', (tester) async {
    var exited = false;
    await tester.pumpWidget(_app(onExit: () async => exited = true));
    await tester.pumpAndSettle();

    await _back(tester);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    expect(find.text('home body'), findsOneWidget);
    expect(exited, isFalse);
  });

  testWidgets('a screen pushed above the shell pops normally', (tester) async {
    var exited = false;
    await tester.pumpWidget(_app(onExit: () async => exited = true));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('home body'));
    GoRouter.of(context).push<void>('/pushed').ignore();
    await tester.pumpAndSettle();
    expect(find.text('pushed body'), findsOneWidget);

    await _back(tester);

    // Back to the tab it came from, with no question and no exit.
    expect(find.text('home body'), findsOneWidget);
    expect(find.text(l10n.exitAppTitle), findsNothing);
    expect(exited, isFalse);
  });
}
