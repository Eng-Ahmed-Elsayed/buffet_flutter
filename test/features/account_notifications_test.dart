import 'dart:async';

import 'package:buffet_app/app/routes.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/material_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/repositories/notifications_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/materials/my_materials_screen.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/favourites_screen.dart';
import 'package:buffet_app/features/settings/settings_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/shared/widgets/notification_bell.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_auth_controller.dart';

final _ar = lookupAppLocalizations(const Locale('ar'));
final _en = lookupAppLocalizations(const Locale('en'));

NotificationDto _n(int id, String kind, {int? orderId, bool isRead = false}) =>
    NotificationDto(
      notificationId: id,
      kind: kind,
      message: 'رسالة $id',
      orderId: orderId,
      createdAtUtc: DateTime.utc(2026, 8, 24, 7),
      isRead: isRead,
    );

/// Answers like the server: once marked, every row comes back read.
class _Repo extends NotificationsRepository {
  _Repo(this.items) : super(Dio());

  List<NotificationDto> items;

  @override
  Future<List<NotificationDto>> fetch({
    required String languageCode,
    required String networkErrorFallback,
    bool unreadOnly = false,
  }) async => items;

  @override
  Future<void> markAllRead({
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    items = [
      for (final n in items)
        NotificationDto(
          notificationId: n.notificationId,
          kind: n.kind,
          message: n.message,
          orderId: n.orderId,
          createdAtUtc: n.createdAtUtc,
          isRead: true,
        ),
    ];
  }
}

/// The notifications screen under a router, with somewhere for a tap to go.
class _Routed extends StatefulWidget {
  const _Routed();

  @override
  State<_Routed> createState() => _RoutedState();
}

class _RoutedState extends State<_Routed> {
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (c, s) => const NotificationsScreen()),
      GoRoute(
        path: Routes.materials,
        builder: (c, s) => const Text('materials-screen'),
      ),
      GoRoute(
        path: Routes.orderStatus,
        builder: (c, s) => const Text('order-screen'),
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Router.withConfig(config: _router);
}

Widget _notifications(_Repo repo, {bool staff = false}) => ProviderScope(
  overrides: [
    notificationsRepositoryProvider.overrideWithValue(repo),
    startsOnQueueProvider.overrideWithValue(staff),
  ],
  child: testApp(home: const _Routed()),
);

class _CountingSignOut extends FakeAuthController {
  _CountingSignOut()
    : super(
        const AuthState(
          stage: AuthStage.signedIn,
          restoredIdentity: (
            role: 'Employee',
            displayName: 'سارة',
            department: 'المالية',
            canOrderForGuests: false,
          ),
        ),
        pinned: true,
      );

  int signOuts = 0;

  @override
  Future<void> signOut() async => signOuts++;
}

void main() {
  setUpAll(loadAppFonts);

  group('notifications', () {
    testWidgets('rows new on opening keep their mark after being marked read', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final repo = _Repo([
        _n(1, 'OrderReady', orderId: 4),
        _n(2, 'DeclarationConfirmed'),
        _n(3, 'OrderCancelled', orderId: 5, isRead: true),
      ]);
      await tester.pumpWidget(_notifications(repo));
      await tester.pumpAndSettle();

      // Marked read on the server and reloaded, every row now says read; the
      // two that were new still carry their mark while they are being read.
      expect(repo.items.every((n) => n.isRead), isTrue);
      // Read as part of each row: the message, the mark, then the time.
      expect(find.bySemanticsLabel(RegExp(_ar.unread)), findsNWidgets(2));
      handle.dispose();
    });

    testWidgets('a declaration outcome opens My materials for an employee', (
      tester,
    ) async {
      await tester.pumpWidget(
        _notifications(_Repo([_n(1, 'DeclarationRejected')])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('رسالة 1'));
      await tester.pumpAndSettle();
      expect(find.text('materials-screen'), findsOneWidget);
    });

    testWidgets('but leads nowhere for staff, who have no materials screen; '
        'nor does low stock, which is about buffet stock', (tester) async {
      await tester.pumpWidget(
        _notifications(
          _Repo([_n(1, 'DeclarationConfirmed'), _n(2, 'LowStock')]),
          staff: true,
        ),
      );
      await tester.pumpAndSettle();

      final tappable = tester
          .widgetList<InkWell>(find.byType(InkWell))
          .where((w) => w.onTap != null);
      expect(tappable, isEmpty);
    });

    testWidgets('the bell says how many are unread, exactly', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [unreadNotificationCountProvider.overrideWithValue(12)],
          child: testApp(
            home: const Scaffold(body: Center(child: NotificationBell())),
            locale: const Locale('en'),
          ),
        ),
      );

      // The badge draws "9+"; a screen reader hears the number.
      expect(find.text('9+'), findsOneWidget);
      final bell = tester.getSemantics(find.byType(IconButton));
      expect(bell.tooltip, _en.notifications);
      expect(bell.label, _en.unreadCount(12));
      handle.dispose();
    });

    testWidgets('an Arabic badge still reads "9+", not "+9"', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [unreadNotificationCountProvider.overrideWithValue(12)],
          child: testApp(
            home: const Scaffold(body: Center(child: NotificationBell())),
          ),
        ),
      );
      final badge = tester.widget<Text>(find.text('9+'));
      expect(badge.textDirection, TextDirection.ltr);
    });
  });

  group('My materials', () {
    testWidgets('the last card clears the declare button, and a balance sits '
        'at the card end', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final materials = [
        for (var i = 1; i <= 8; i++)
          MyMaterialDto(
            itemId: i,
            nameAr: 'مادة $i',
            unit: 'g',
            quantity: 5,
            servingsLeft: 2,
            level: 'Ok',
            imageUrl: null,
          ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [myMaterialsProvider.overrideWith((r) async => materials)],
          child: testApp(
            home: const MyMaterialsScreen(),
            locale: const Locale('en'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();

      final lastCard = tester.getRect(find.text('مادة 8'));
      final fab = tester.getRect(find.byType(FloatingActionButton));
      final lastServings = tester.getRect(find.text(_en.servingsLeft(2)).last);
      expect(lastServings.bottom, lessThanOrEqualTo(fab.top));

      // A Flexible beside the Expanded name split the row in half, so the
      // balance ended mid-card.
      final balance = tester.getRect(find.textContaining('5').last);
      expect(balance.right, greaterThan(lastCard.right));
      expect(balance.right, greaterThan(320 * 0.8));
    });
  });

  testWidgets('the empty Favourites tab says where to save one, and leads on', (
    tester,
  ) async {
    Widget screen({required bool returnsPick}) => ProviderScope(
      overrides: [
        favouritesProvider.overrideWith(
          (r) async => const FavouritesResponse(favourites: []),
        ),
        catalogueProvider.overrideWith(
          (r) => Completer<CatalogueResponse>().future,
        ),
      ],
      child: testApp(home: FavouritesScreen(returnsPick: returnsPick)),
    );

    await tester.pumpWidget(screen(returnsPick: false));
    await tester.pumpAndSettle();
    expect(find.text(_ar.favouritesEmptyHint), findsOneWidget);
    expect(find.text(_ar.orderADrink), findsOneWidget);

    // Picking for a composer: the composer is the way on.
    await tester.pumpWidget(screen(returnsPick: true));
    await tester.pumpAndSettle();
    expect(find.text(_ar.orderADrink), findsNothing);
  });

  testWidgets('sign out asks first, and Cancel keeps the session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = _CountingSignOut();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((r) => auth)],
        child: testApp(home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(_ar.signOut));
    await tester.pumpAndSettle();
    expect(find.text(_ar.signOutConfirmTitle), findsOneWidget);
    await tester.tap(find.text(_ar.cancel));
    await tester.pumpAndSettle();
    expect(auth.signOuts, 0);

    await tester.tap(find.text(_ar.signOut));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(_ar.signOut),
      ),
    );
    await tester.pumpAndSettle();
    expect(auth.signOuts, 1);
  });
}
