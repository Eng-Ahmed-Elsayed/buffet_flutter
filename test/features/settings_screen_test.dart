import 'package:buffet_app/data/api/api_client.dart';
import 'package:buffet_app/data/local/biometric_enrolment_guard.dart';
import 'package:buffet_app/data/local/biometric_service.dart';
import 'package:buffet_app/data/local/notification_settings.dart';
import 'package:buffet_app/data/local/preferences_store.dart';
import 'package:buffet_app/data/local/secure_token_store.dart';
import 'package:buffet_app/data/repositories/auth_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/settings/settings_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';

Widget wrap({
  Locale locale = const Locale('ar'),
  String? role,
  NotificationSettings? notifications,
}) => ProviderScope(
  overrides: [
    if (notifications != null)
      notificationSettingsProvider.overrideWithValue(notifications),
    if (role != null)
      authControllerProvider.overrideWith(
        (ref) => _FakeAuthController(
          AuthState(
            stage: AuthStage.signedIn,
            restoredIdentity: (
              role: role,
              displayName: 'سارة',
              department: 'المالية',
              canOrderForGuests: false,
            ),
          ),
        ),
      ),
  ],
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

  group('SettingsScreen — the way into My materials', () {
    testWidgets('is on the account for an employee', (tester) async {
      // It moved here from a Home tile when the tab bar arrived.
      await tester.pumpWidget(
        wrap(locale: const Locale('en'), role: 'Employee'),
      );
      await tester.pump();
      expect(find.text('My materials'), findsOneWidget);
    });

    testWidgets('is absent for staff, who reach this screen from the queue', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(locale: const Locale('en'), role: 'Staff'));
      await tester.pump();
      expect(find.text('My materials'), findsNothing);
      // Anchored on something that IS there, so this cannot pass on a blank
      // screen.
      expect(find.text('Sign out'), findsOneWidget);
    });
  });

  testWidgets('the foot carries the installed version and build', (
    tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'buffet_app',
      packageName: 'eg.defi.buffet',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(locale: const Locale('en'), role: 'Employee'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Version'), findsOneWidget);
    expect(find.textContaining('1.2.3 (45)'), findsOneWidget);
  });

  group('notifications switched off', () {
    testWidgets('says so, and opens the system settings', (tester) async {
      final notifications = _FakeNotificationSettings(enabled: false);
      await tester.pumpWidget(
        wrap(
          locale: const Locale('en'),
          role: 'Employee',
          notifications: notifications,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notifications are off'), findsOneWidget);
      await tester.tap(find.text('Turn on in settings'));
      expect(notifications.opened, 1);
    });

    testWidgets('draws nothing while they are on', (tester) async {
      await tester.pumpWidget(
        wrap(
          locale: const Locale('en'),
          role: 'Employee',
          notifications: _FakeNotificationSettings(enabled: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Notifications are off'), findsNothing);
    });

    testWidgets('looks again when the app comes back from settings', (
      tester,
    ) async {
      final notifications = _FakeNotificationSettings(enabled: false);
      await tester.pumpWidget(
        wrap(
          locale: const Locale('en'),
          role: 'Employee',
          notifications: notifications,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notifications are off'), findsOneWidget);

      notifications.isEnabled = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Notifications are off'), findsNothing);
    });
  });
}

/// Holds the auth machine at a chosen state, as the capture harness does.
class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initial)
    : super(
        AuthRepository(
          dio: Dio(),
          tokenStore: const SecureTokenStore(FlutterSecureStorage()),
          preferences: const PreferencesStore(FlutterSecureStorage()),
        ),
        AuthEvents(),
        const BiometricService(_InertAuthenticator()),
        const BiometricEnrolmentGuard(),
      ) {
    state = initial;
  }
}

class _InertAuthenticator implements BiometricAuthenticator {
  const _InertAuthenticator();

  @override
  Future<bool> canCheckBiometrics() async => false;

  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<List<BiometricType>> availableBiometrics() async => const [];

  @override
  Future<bool> authenticate({required String localizedReason}) async => false;
}

class _FakeNotificationSettings extends NotificationSettings {
  _FakeNotificationSettings({required bool enabled})
    : isEnabled = enabled,
      super(FlutterLocalNotificationsPlugin());

  bool isEnabled;
  int opened = 0;

  @override
  Future<bool?> enabled() async => isEnabled;

  @override
  Future<void> open() async => opened++;
}
