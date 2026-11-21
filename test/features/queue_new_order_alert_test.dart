import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/local/order_alerts.dart';
import 'package:buffet_app/data/local/preferences_store.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:buffet_app/data/repositories/queue_repository.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/staff_queue/new_order_alert.dart';
import 'package:buffet_app/features/staff_queue/queue_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

final _l10n = lookupAppLocalizations(const Locale('ar'));

StaffOrderDto _order(int id) => StaffOrderDto(
  orderId: id,
  status: 'Pending',
  createdAtUtc: DateTime.utc(2026, 8, 24, 7),
  readyAtUtc: null,
  requesterDisplayName: 'موظف $id',
  department: 'المالية',
  locationText: 'الدور الثالث',
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

class _Repository extends QueueRepository {
  _Repository(this.queue) : super(Dio());

  List<StaffOrderDto> queue;

  @override
  Future<List<StaffOrderDto>> fetchQueue({
    required String languageCode,
    required String networkErrorFallback,
  }) async => queue;

  @override
  Future<List<StaffOrderDto>> fetchReadyForHandover({
    required String languageCode,
    required String networkErrorFallback,
  }) async => const [];
}

/// Records the new-order alerts instead of showing them.
class _Alerts extends OrderAlerts {
  _Alerts() : super(FlutterLocalNotificationsPlugin());

  final titles = <String>[];

  @override
  Future<void> initialise({
    required String readyChannelName,
    required String readyChannelDescription,
    required String cancelledChannelName,
    required String cancelledChannelDescription,
    required String newOrderChannelName,
    required String newOrderChannelDescription,
  }) async {}

  @override
  Future<void> newOrders({required String title, required String body}) async =>
      titles.add(title);
}

/// The setting, fixed for a test.
class _Setting extends QueueAlertsSetting {
  _Setting(bool enabled) : super(const PreferencesStore(FlutterSecureStorage())) {
    state = enabled;
  }
}

Future<_Alerts> _pump(
  WidgetTester tester,
  _Repository repository, {
  bool enabled = true,
  Set<int> ownOrders = const {},
}) async {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final alerts = _Alerts();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        queueRepositoryProvider.overrideWithValue(repository),
        notificationsProvider.overrideWith((ref) async => const []),
        orderAlertsProvider.overrideWithValue(alerts),
        queueAlertsSettingProvider.overrideWith((ref) => _Setting(enabled)),
        selfPlacedOrdersProvider.overrideWithValue({...ownOrders}),
      ],
      child: const MaterialApp(
        locale: Locale('ar'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('ar'), Locale('en')],
        home: QueueScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return alerts;
}

Future<void> _poll(WidgetTester tester) async {
  await tester.pump(ApiConfig.queuePollInterval);
  await tester.pumpAndSettle();
}

void main() {
  group('NewOrderDetector', () {
    test('nothing is new on the first look or a silent one', () {
      final detector = NewOrderDetector();
      expect(detector.observe([1, 2]), isEmpty);
      expect(detector.observe([1, 2, 3], silent: true), isEmpty);
      // 3 was seen silently; it is not announced later.
      expect(detector.observe([1, 2, 3]), isEmpty);
      expect(detector.observe([2, 3, 4]), [4]);
      // An order that left and came back is not new.
      expect(detector.observe([1, 4]), isEmpty);
    });
  });

  testWidgets('not on the first load', (tester) async {
    final alerts = await _pump(tester, _Repository([_order(1), _order(2)]));
    expect(alerts.titles, isEmpty);
  });

  testWidgets('exactly one alert for a refresh with new orders, once', (
    tester,
  ) async {
    final repository = _Repository([_order(1)]);
    final alerts = await _pump(tester, repository);

    repository.queue = [_order(1), _order(2), _order(3)];
    await _poll(tester);
    expect(alerts.titles, [_l10n.newOrdersAlertTitle(2)]);

    // The same orders on the next refresh are not new again.
    await _poll(tester);
    expect(alerts.titles, hasLength(1));
  });

  testWidgets("not for this device's own order", (tester) async {
    final repository = _Repository([_order(1)]);
    final alerts = await _pump(tester, repository, ownOrders: {7});

    repository.queue = [_order(1), _order(7)];
    await _poll(tester);
    expect(alerts.titles, isEmpty);
  });

  testWidgets('not when switched off', (tester) async {
    final repository = _Repository([_order(1)]);
    final alerts = await _pump(tester, repository, enabled: false);

    repository.queue = [_order(1), _order(2)];
    await _poll(tester);
    expect(alerts.titles, isEmpty);
  });

  testWidgets('the catch-up on returning to the app is silent', (
    tester,
  ) async {
    final repository = _Repository([_order(1)]);
    final alerts = await _pump(tester, repository);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    repository.queue = [_order(1), _order(2)];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('موظف 2'), findsOneWidget);
    expect(alerts.titles, isEmpty);

    // And what it caught up on is not announced afterwards either.
    await _poll(tester);
    expect(alerts.titles, isEmpty);
  });
}
