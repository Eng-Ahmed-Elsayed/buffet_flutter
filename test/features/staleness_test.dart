import 'package:buffet_app/data/api/api_config.dart';
import 'package:buffet_app/data/api/api_exception.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:buffet_app/data/repositories/order_repository.dart';
import 'package:buffet_app/data/repositories/queue_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/home/home_screen.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:buffet_app/features/order/order_status_screen.dart';
import 'package:buffet_app/features/staff_queue/queue_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/error_text.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/app_harness.dart';

final _l10n = lookupAppLocalizations(const Locale('ar'));

const _offline = ApiException(
  message: '',
  statusCode: null,
  isNetworkFailure: true,
);

OrderSummaryDto _order(String status) => OrderSummaryDto(
  orderId: 41,
  status: status,
  createdAtUtc: DateTime.utc(2026, 8, 20, 7),
  readyAtUtc: null,
  handledAtUtc: null,
  locationText: 'مكتبي',
  onBehalfOfName: null,
  notes: '',
  lines: const [
    OrderLineDto(
      drinkItemId: 1,
      drinkNameAr: 'قهوة',
      sugarSpoons: 1,
      variantId: null,
      sugarItemId: null,
      extraItemIds: [],
      lineNote: null,
      drinkFromOwn: false,
      sugarFromOwn: false,
      ownExtraItemIds: [],
    ),
  ],
);

const _emptyMenu = CatalogueResponse(
  drinks: [],
  sugars: [],
  extras: [],
  locations: [],
);

StaffOrderDto _staffOrder() => StaffOrderDto(
  orderId: 7,
  status: 'Pending',
  createdAtUtc: DateTime.utc(2026, 8, 24, 7),
  readyAtUtc: null,
  requesterDisplayName: 'سارة العتيبي',
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

class _FlakyOrders implements OrderRepository {
  bool fail = false;

  @override
  Future<OrderSummaryDto> fetchOrder({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    if (fail) throw _offline;
    return _order('InProgress');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FlakyQueue extends QueueRepository {
  _FlakyQueue() : super(Dio());

  bool fail = false;

  @override
  Future<List<StaffOrderDto>> fetchQueue({
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    if (fail) throw _offline;
    return [_staffOrder()];
  }

  @override
  Future<List<StaffOrderDto>> fetchReadyForHandover({
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    if (fail) throw _offline;
    return const [];
  }
}

/// The status screen calls `context.canPop()`, so it needs a router above
/// it. Built in build, never at file load (CLAUDE.md).
class _RoutedStatus extends StatelessWidget {
  const _RoutedStatus();

  @override
  Widget build(BuildContext context) => Router.withConfig(
    config: GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => const OrderStatusScreen(orderId: 41),
        ),
      ],
    ),
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  group('describeError never shows a placeholder', () {
    test('a network failure reads as the network message', () {
      expect(describeError(_offline, _l10n), _l10n.networkError);
    });

    test("the server's own message is shown as-is", () {
      const refused = ApiException(message: 'مرفوض', statusCode: 400);
      expect(describeError(refused, _l10n), 'مرفوض');
    });

    test('a reply without a message reads as the generic message, never '
        'blank', () {
      // An HTML error page during a restart: a response, but no message.
      const bare = ApiException(message: '', statusCode: 503);
      expect(describeError(bare, _l10n), _l10n.genericError);
    });

    test('anything else reads as the network message', () {
      expect(describeError(StateError('x'), _l10n), _l10n.networkError);
    });
  });

  group('a failed refresh keeps what is on screen, and says so', () {
    testWidgets('My orders keeps its list', (tester) async {
      _tall(tester);
      var failing = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myOrdersProvider.overrideWith((ref) async {
              if (failing) throw _offline;
              return [_order('Ready')];
            }),
            favouritesProvider.overrideWith(
              (ref) async => const FavouritesResponse(favourites: []),
            ),
            catalogueProvider.overrideWith((ref) async => _emptyMenu),
          ],
          child: testApp(home: const MyOrdersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      failing = true;
      ProviderScope.containerOf(tester.element(find.byType(MyOrdersScreen)))
          .invalidate(myOrdersProvider);
      await tester.pumpAndSettle();

      // The Ready order is still there, with the notice above it.
      expect(find.text(_l10n.statusReady), findsOneWidget);
      expect(find.text(_l10n.couldNotRefreshTitle), findsOneWidget);
      expect(find.text(_l10n.genericError), findsNothing);
    });

    testWidgets('the tracking screen keeps its order', (tester) async {
      _tall(tester);
      final repository = _FlakyOrders();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderRepositoryProvider.overrideWithValue(repository),
            catalogueProvider.overrideWith((ref) async => _emptyMenu),
          ],
          child: testApp(home: const _RoutedStatus()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      repository.fail = true;
      await tester.pump(ApiConfig.orderPollInterval);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(_l10n.couldNotRefreshTitle), findsOneWidget);
      expect(find.text(_l10n.statusInProgress), findsWidgets);
    });

    testWidgets('the queue keeps its orders', (tester) async {
      _tall(tester);
      final repository = _FlakyQueue();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            queueRepositoryProvider.overrideWithValue(repository),
            notificationsProvider.overrideWith((ref) async => const []),
          ],
          child: testApp(home: const QueueScreen()),
        ),
      );
      await tester.pumpAndSettle();

      repository.fail = true;
      await tester.pump(ApiConfig.queuePollInterval);
      await tester.pumpAndSettle();

      expect(find.textContaining('سارة'), findsOneWidget);
      expect(find.text(_l10n.couldNotRefreshTitle), findsOneWidget);
    });
  });

  group("the bell's badge is refreshed, not read once at sign-in", () {
    testWidgets('the queue reloads it with every refresh', (tester) async {
      _tall(tester);
      var loads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            queueRepositoryProvider.overrideWithValue(_FlakyQueue()),
            notificationsProvider.overrideWith((ref) async {
              loads++;
              return const [];
            }),
          ],
          child: testApp(home: const QueueScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final before = loads;

      await tester.pump(ApiConfig.queuePollInterval);
      await tester.pumpAndSettle();

      expect(loads, greaterThan(before));
    });

    testWidgets('Home reloads it on resume', (tester) async {
      _tall(tester);
      var loads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogueProvider.overrideWith((ref) async => _emptyMenu),
            favouritesProvider.overrideWith(
              (ref) async => const FavouritesResponse(favourites: []),
            ),
            canOrderForGuestsProvider.overrideWith((ref) => false),
            myOrdersProvider.overrideWith((ref) async => const []),
            notificationsProvider.overrideWith((ref) async {
              loads++;
              return const [];
            }),
          ],
          child: testApp(home: const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final before = loads;

      // Out to the background and back, one legal step at a time.
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();

      expect(loads, greaterThan(before));
    });
  });

  group('the notifications list survives a failed background refresh', () {
    testWidgets('the list stays, with the notice', (tester) async {
      _tall(tester);
      var failing = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationsProvider.overrideWith((ref) async {
              if (failing) throw _offline;
              return [
                NotificationDto(
                  notificationId: 1,
                  kind: 'DeclarationConfirmed',
                  message: 'تم تأكيد استلام السكر',
                  orderId: null,
                  isRead: true,
                  createdAtUtc: DateTime.utc(2026, 8, 20, 7),
                ),
              ];
            }),
          ],
          child: testApp(home: const NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      failing = true;
      ProviderScope.containerOf(
        tester.element(find.byType(NotificationsScreen)),
      ).invalidate(notificationsProvider);
      await tester.pumpAndSettle();

      expect(find.textContaining('تم تأكيد استلام السكر'), findsOneWidget);
      expect(find.text(_l10n.couldNotRefreshTitle), findsOneWidget);
    });
  });
}
