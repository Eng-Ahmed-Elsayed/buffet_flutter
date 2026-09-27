import 'package:buffet_app/app/landing_prompts.dart';
import 'package:buffet_app/app/locale_controller.dart';
import 'package:buffet_app/data/api/api_exception.dart';
import 'package:buffet_app/data/local/order_alerts.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:buffet_app/data/repositories/queue_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/auth/login_screen.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/onboarding/onboarding_screen.dart';
import 'package:buffet_app/features/settings/biometric_enrolment_sheet.dart';
import 'package:buffet_app/features/staff_queue/queue_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/theme/motion.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_controller.dart';

final _ar = lookupAppLocalizations(const Locale('ar'));
final _en = lookupAppLocalizations(const Locale('en'));

/// The real locale controller drives the app, so a switch that moved the
/// control but not the language would fail.
class _Localised extends ConsumerWidget {
  const _Localised(this.home);

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    locale: ref.watch(localeControllerProvider),
    supportedLocales: LocaleController.supported,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

class _RefusingSignIn extends FakeAuthController {
  _RefusingSignIn()
    : super(const AuthState(stage: AuthStage.signedOut), pinned: true);

  @override
  Future<void> signIn({
    required String username,
    required String password,
    required String languageCode,
    required String networkErrorFallback,
  }) async => throw const ApiException(
    message: 'بيانات الدخول غير صحيحة',
    statusCode: 401,
  );
}

class _CountingAlerts extends OrderAlerts {
  _CountingAlerts() : super(FlutterLocalNotificationsPlugin());

  int initialised = 0;

  @override
  Future<void> initialise({
    required String readyChannelName,
    required String readyChannelDescription,
    required String cancelledChannelName,
    required String cancelledChannelDescription,
  }) async => initialised++;
}

StaffOrderDto _order(int id) => StaffOrderDto(
  orderId: id,
  status: 'Pending',
  createdAtUtc: DateTime.utc(2026, 8, 24, 7),
  readyAtUtc: null,
  requesterDisplayName: 'سارة العتيبي',
  department: 'المالية',
  locationText: '',
  onBehalfOfName: null,
  notes: '',
  waitingSeconds: 30,
  lines: const [
    StaffOrderLineDto(
      drinkItemId: 1,
      drinkNameAr: 'شاي',
      variantNameAr: null,
      sugarSpoons: 1,
      sugarNameAr: null,
      extraNamesAr: [],
      lineNote: null,
      drinkSourceOwnerName: '',
      sugarSourceOwnerName: '',
      extraSources: [],
    ),
  ],
);

class _Queue extends QueueRepository {
  _Queue() : super(Dio());

  final served = <int>[];

  @override
  Future<List<StaffOrderDto>> fetchQueue({
    required String languageCode,
    required String networkErrorFallback,
  }) async => [_order(5)];

  @override
  Future<List<StaffOrderDto>> fetchReadyForHandover({
    required String languageCode,
    required String networkErrorFallback,
  }) async => const [];

  @override
  Future<ServeResultDto> markReady({
    required int orderId,
    required bool deliverNow,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    served.add(orderId);
    return ServeResultDto(orderId: orderId, status: 'Completed', warnings: []);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> tall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('the first-launch explainer can be read in English', (
    tester,
  ) async {
    await tall(tester);
    await tester.pumpWidget(
      const ProviderScope(child: _Localised(OnboardingScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text(_ar.onboardingOrderTitle), findsOneWidget);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text(_en.onboardingOrderTitle), findsOneWidget);
  });

  testWidgets('a sign-in error goes when the language changes', (tester) async {
    await tall(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((r) => _RefusingSignIn()),
        ],
        child: const _Localised(LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.c');
    await tester.enterText(find.byType(TextFormField).at(1), 'x');
    await tester.tap(find.text(_ar.signIn));
    await tester.pumpAndSettle();
    expect(find.text('بيانات الدخول غير صحيحة'), findsOneWidget);

    // It came back in Arabic; left under an English screen it would stay so.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('بيانات الدخول غير صحيحة'), findsNothing);
  });

  testWidgets('the permission prompt waits for the biometric offer', (
    tester,
  ) async {
    final alerts = _CountingAlerts();
    final auth = FakeAuthController(
      const AuthState(stage: AuthStage.signedIn, offerBiometricEnrolment: true),
      pinned: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((r) => auth),
          orderAlertsProvider.overrideWithValue(alerts),
        ],
        child: _Localised(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => prepareLandingPrompts(context, ref),
              child: const Text('land'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('land'));
    await tester.pumpAndSettle();

    // Stacked on the biometric sheet, it was answered blind.
    expect(alerts.initialised, 0);

    auth
      ..pinned = false
      ..declineBiometricEnrolment();
    // Answered, but its sheet is still closing: a permission dialog opened
    // now paused the app with the sheet frozen on screen (emulator).
    await tester.pump();
    expect(alerts.initialised, 0);
    await tester.pump(Motion.sheetExit);
    await tester.pumpAndSettle();
    expect(alerts.initialised, 1);
  });

  testWidgets('tapping away from the biometric offer clears it', (
    tester,
  ) async {
    await tall(tester);
    final auth = FakeAuthController(
      const AuthState(stage: AuthStage.signedIn, offerBiometricEnrolment: true),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((r) => auth)],
        child: _Localised(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => BiometricEnrolmentSheet.show(context, ref),
              child: const Text('offer'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    auth.state = auth.state.copyWith(offerBiometricEnrolment: true);
    await tester.tap(find.text('offer'));
    await tester.pumpAndSettle();
    expect(find.byType(BiometricEnrolmentSheet), findsOneWidget);

    // Left standing, the permission prompts waiting on it waited for good.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(BiometricEnrolmentSheet), findsNothing);
    expect(auth.state.offerBiometricEnrolment, isFalse);
  });

  group('the staff queue', () {
    Future<(FakeAuthController, _Queue)> open(
      WidgetTester tester, {
      bool sessionNotRefreshed = false,
    }) async {
      await tall(tester);
      final auth = FakeAuthController(
        AuthState(
          stage: AuthStage.signedIn,
          reSignInAfterPasswordChangeFailed: sessionNotRefreshed,
        ),
        pinned: true,
      );
      final queue = _Queue();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith((r) => auth),
            queueRepositoryProvider.overrideWithValue(queue),
            notificationsProvider.overrideWith((ref) async => const []),
            orderAlertsProvider.overrideWithValue(_CountingAlerts()),
          ],
          child: const _Localised(QueueScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return (auth, queue);
    }

    testWidgets('signing out sends a serve still in its window', (
      tester,
    ) async {
      final (auth, queue) = await open(tester);
      await tester.tap(find.text(_ar.readyAndDelivered));
      await tester.pump();
      expect(queue.served, isEmpty);

      // What sign-out runs first, while the token is still valid. From the
      // queue's dispose alone the serve went after the token, and was lost.
      for (final task in auth.beforeSignOut.toList()) {
        await task();
      }
      expect(queue.served, [5]);
      await tester.pumpAndSettle();
    });

    testWidgets('the session notice shows here too, and can be dismissed', (
      tester,
    ) async {
      final (auth, _) = await open(tester, sessionNotRefreshed: true);
      expect(find.text(_ar.sessionNotRefreshed), findsOneWidget);

      auth.pinned = false;
      await tester.tap(find.byTooltip(_ar.dismiss));
      await tester.pumpAndSettle();
      expect(find.text(_ar.sessionNotRefreshed), findsNothing);
    });
  });

  test('counts read as Arabic counts', () {
    expect(_ar.servingsLeft(3), 'تبقّت 3 أكواب');
    expect(_ar.servingsLeft(2), 'تبقّى كوبان');
    expect(_ar.favouritesFullBody(20), contains('20 طلبًا مفضلًا'));
    expect(_ar.maxLinesReachedBody(5), contains('5 مشروبات'));
    expect(_en.maxLinesReachedBody(1), contains('one drink'));
  });
}
