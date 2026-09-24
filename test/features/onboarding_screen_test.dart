import 'package:buffet_app/data/local/preferences_store.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/onboarding/onboarding_controller.dart';
import 'package:buffet_app/features/onboarding/onboarding_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

/// Records `markSeen` instead of writing to storage, which has no plugin
/// behind it under test.
class _FakeOnboarding extends OnboardingController {
  _FakeOnboarding() : super(const PreferencesStore(FlutterSecureStorage())) {
    state = false;
  }

  int marked = 0;

  @override
  Future<void> markSeen() async {
    marked++;
    state = true;
  }
}

Future<_FakeOnboarding> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  final fake = _FakeOnboarding();
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [onboardingControllerProvider.overrideWith((ref) => fake)],
      child: testApp(home: const OnboardingScreen(), locale: locale),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    await loadAppFonts();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('it explains the service, one slide at a time', (tester) async {
    await _pump(tester);
    expect(find.text(l10n.onboardingOrderTitle), findsOneWidget);

    await tester.tap(find.text(l10n.onboardingNext));
    await tester.pumpAndSettle();
    expect(find.text(l10n.onboardingReadyTitle), findsOneWidget);
  });

  testWidgets('Skip ends it, without walking every slide', (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.text(l10n.onboardingSkip));
    await tester.pumpAndSettle();

    expect(fake.marked, 1);
  });

  testWidgets('Sign in ends it from the first slide', (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, l10n.signIn));
    await tester.pumpAndSettle();

    expect(fake.marked, 1);
  });

  testWidgets('on the last slide the primary action signs in, once', (
    tester,
  ) async {
    final fake = await _pump(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text(l10n.onboardingNext));
      await tester.pumpAndSettle();
    }
    expect(find.text(l10n.onboardingOwnTitle), findsOneWidget);

    // One "Sign in", not two: the outlined twin is gone once the primary
    // button says the same thing.
    expect(find.text(l10n.signIn), findsOneWidget);
    expect(find.text(l10n.onboardingNext), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, l10n.signIn));
    await tester.pumpAndSettle();
    expect(fake.marked, 1);
  });

  testWidgets('it reads right to left in Arabic', (tester) async {
    await _pump(tester, locale: const Locale('ar'));

    expect(
      Directionality.of(tester.element(find.byType(OnboardingScreen))),
      TextDirection.rtl,
    );
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(find.text(ar.onboardingOrderTitle), findsOneWidget);
  });

  group('someone who already uses the app never sees it', () {
    // Everyone who signed in before the explainer existed has no flag. If only
    // the explainer's own buttons wrote it, their next 401 or sign-out would
    // send them through three slides before the "session expired" sign-in.
    final writes = <String>[];

    setUp(() {
      writes.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              if (call.method == 'write') {
                writes.add((call.arguments as Map)['key'] as String);
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null,
          );
    });

    for (final stage in [
      AuthStage.signedIn,
      AuthStage.locked,
      AuthStage.mustChangePassword,
    ]) {
      test('a session at $stage marks it seen and saves that', () async {
        final container = ProviderContainer(
          overrides: [authStageProvider.overrideWithValue(stage)],
        );
        addTearDown(container.dispose);

        expect(container.read(onboardingControllerProvider), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(writes, contains('pref_onboarding_seen'));
      });
    }

    test('signed out with no flag, it is still shown', () async {
      final container = ProviderContainer(
        overrides: [authStageProvider.overrideWithValue(AuthStage.signedOut)],
      );
      addTearDown(container.dispose);

      container.read(onboardingControllerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(onboardingControllerProvider), isFalse);
      expect(writes, isEmpty);
    });
  });
}
