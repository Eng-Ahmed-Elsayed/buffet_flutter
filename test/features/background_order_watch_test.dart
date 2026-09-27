import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/api/api_exception.dart';
import 'package:buffet_app/data/local/order_alerts.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/push/push_controller.dart';
import 'package:buffet_app/data/repositories/order_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/home/home_screen.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/order/background_order_watch.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

OrderSummaryDto _order(int id, String status) => OrderSummaryDto(
  orderId: id,
  status: status,
  createdAtUtc: DateTime.utc(2026, 8, 20, 7),
  readyAtUtc: null,
  handledAtUtc: null,
  locationText: '',
  onBehalfOfName: null,
  notes: '',
  lines: const [],
);

const _interval = ApiConfig.backgroundPollInterval;
const _window = ApiConfig.backgroundWatchWindow;

void main() {
  group('BackgroundOrderWatch', () {
    // Widget tests for the fake clock: timers advance with tester.pump.
    late DateTime now;
    late List<List<OrderSummaryDto>> seen;
    late int looks;

    BackgroundOrderWatch watch(
      Future<List<OrderSummaryDto>> Function() look,
    ) => BackgroundOrderWatch(
      look: () {
        looks++;
        return look();
      },
      onOrders: seen.add,
      interval: _interval,
      window: _window,
      clock: () => now,
    );

    Future<void> wait(WidgetTester tester, Duration duration) async {
      now = now.add(duration);
      await tester.pump(duration);
    }

    setUp(() {
      now = DateTime(2026, 9, 27, 9);
      seen = [];
      looks = 0;
    });

    testWidgets('nothing still being made, nothing to watch', (tester) async {
      final w = watch(() async => [_order(1, 'Ready')])
        ..start([_order(1, 'Ready'), _order(2, 'Completed')]);
      expect(w.isWatching, isFalse);
      await wait(tester, _interval);
      expect(looks, 0);
    });

    testWidgets('looks every interval, and stops once nothing is live', (
      tester,
    ) async {
      var status = 'InProgress';
      final w = watch(() async => [_order(1, status)])
        ..start([_order(1, 'Pending')]);
      expect(w.isWatching, isTrue);

      await wait(tester, _interval);
      await wait(tester, _interval);
      expect(looks, 2);
      expect(w.isWatching, isTrue);

      status = 'Ready';
      await wait(tester, _interval);
      expect(seen.last.single.status, 'Ready');
      expect(w.isWatching, isFalse);
      await wait(tester, _interval);
      expect(looks, 3);
    });

    testWidgets('gives up when the window runs out', (tester) async {
      final w = watch(() async => [_order(1, 'Pending')])
        ..start([_order(1, 'Pending')]);
      for (var i = 0; i < 20; i++) {
        await wait(tester, _interval);
      }
      expect(w.isWatching, isFalse);
      // 180s at one look per 10s, the last tick finding the window closed.
      expect(looks, _window.inSeconds ~/ _interval.inSeconds - 1);
    });

    testWidgets('a failed look is skipped, not the end', (tester) async {
      var fail = true;
      final w = watch(() async {
        if (fail) throw const ApiException(message: '', statusCode: null);
        return [_order(1, 'Ready')];
      })..start([_order(1, 'Pending')]);

      await wait(tester, _interval);
      expect(w.isWatching, isTrue);
      expect(seen, isEmpty);

      fail = false;
      await wait(tester, _interval);
      expect(seen, hasLength(1));
      expect(w.isWatching, isFalse);
    });
  });

  group('Home in the background', () {
    setUpAll(loadAppFonts);

    Future<(_Alerts, _Orders)> pump(
      WidgetTester tester, {
      required bool pushRegistered,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final alerts = _Alerts();
      final repository = _Orders([_order(41, 'InProgress')]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderAlertsProvider.overrideWithValue(alerts),
            orderRepositoryProvider.overrideWithValue(repository),
            pushControllerProvider.overrideWithValue(_Push(pushRegistered)),
            myOrdersProvider.overrideWith((ref) async => repository.orders),
            catalogueProvider.overrideWith(
              (ref) async => const CatalogueResponse(
                drinks: [],
                sugars: [],
                extras: [],
                locations: [],
              ),
            ),
            favouritesProvider.overrideWith(
              (ref) async => const FavouritesResponse(favourites: []),
            ),
            canOrderForGuestsProvider.overrideWith((ref) => false),
            notificationsProvider.overrideWith((ref) async => const []),
          ],
          child: testApp(home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return (alerts, repository);
    }

    void leave(WidgetTester tester) {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    void comeBack(WidgetTester tester) {
      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    }

    testWidgets('with no push, a drink turning Ready in a pocket chimes', (
      tester,
    ) async {
      final (alerts, repository) = await pump(tester, pushRegistered: false);
      leave(tester);

      repository.orders = [_order(41, 'Ready')];
      // No frames in the background: the look must not wait on one.
      await tester.pump(_interval);
      await tester.pump(_interval);
      expect(alerts.ready, [41]);

      // Back on screen, the change is showing: no second chime.
      comeBack(tester);
      await tester.pumpAndSettle();
      expect(alerts.ready, [41]);
    });

    testWidgets('with push, the server announces it and the app stays quiet', (
      tester,
    ) async {
      final (alerts, repository) = await pump(tester, pushRegistered: true);
      leave(tester);

      repository.orders = [_order(41, 'Ready')];
      await tester.pump(_interval * 3);
      expect(repository.looks, 0);
      expect(alerts.ready, isEmpty);
      comeBack(tester);
      await tester.pumpAndSettle();
    });
  });
}

class _Alerts extends OrderAlerts {
  _Alerts() : super(FlutterLocalNotificationsPlugin());

  final ready = <int>[];

  @override
  Future<void> orderReady({
    required int orderId,
    required String title,
    required String body,
  }) async => ready.add(orderId);
}

class _Orders extends OrderRepository {
  _Orders(this.orders) : super(Dio());

  List<OrderSummaryDto> orders;
  int looks = 0;

  @override
  Future<List<OrderSummaryDto>> fetchMyOrders({
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    looks++;
    return orders;
  }
}

class _Push extends PushController {
  _Push(this._registered) : super(Dio());

  final bool _registered;

  @override
  bool get isRegistered => _registered;
}
