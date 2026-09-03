@TestOn('vm')
library;

/// Every screen must fit the narrowest phone it will meet, at every text scale
/// the platform can hand it.
///
/// This file exists because four separate overflows shipped without one: the
/// home action grid and the composer's drink grid both fixed a tile HEIGHT via
/// childAspectRatio, so a label needing more room overflowed rather than
/// growing — at the DEFAULT text scale, not merely at the accessibility ones.
/// The favourites heading (then the usual-order card's) and the orders list's
/// status word did the same horizontally at 2x.
///
/// 320dp is the floor: it is the narrowest width Android reports on a phone in
/// portrait, and Arabic is checked alongside English because the two wrap at
/// different lengths.
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/material_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:buffet_app/data/repositories/order_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/auth/login_screen.dart';
import 'package:buffet_app/features/home/home_screen.dart';
import 'package:buffet_app/features/materials/my_materials_screen.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/favourites_screen.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:buffet_app/features/order/order_mode.dart';
import 'package:buffet_app/features/order/order_status_screen.dart';
import 'package:buffet_app/features/settings/settings_screen.dart';
import 'package:buffet_app/features/staff_queue/widgets/queue_card.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

CatalogueItemDto _d(int id, String n) => CatalogueItemDto(
  itemId: id,
  nameAr: n,
  nameEn: n,
  category: 'Drink',
  unit: 'ج',
  imageUrl: null,
  inStock: true,
  hasOwnStock: id == 2,
  ownServingsLeft: 0,
  variants: const [],
  allowedExtraItemIds: null,
);

final _cat = CatalogueResponse(
  drinks: [_d(1, 'قهوة تركي سادة'), _d(2, 'شاي بالنعناع')],
  sugars: const [],
  extras: const [],
  locations: const [],
  maxLines: 5,
  maxBuffetDrinks: 1,
);

final _orders = [
  OrderSummaryDto(
    orderId: 7,
    status: 'Ready',
    createdAtUtc: DateTime.utc(2026, 8, 20, 7),
    readyAtUtc: DateTime.utc(2026, 8, 20, 7, 5),
    handledAtUtc: null,
    locationText: 'الدور الثالث، مكتب ٣١٢',
    onBehalfOfName: 'ضيف الوزارة',
    notes: 'بدون لبن',
    lines: const [],
  ),
  OrderSummaryDto(
    orderId: 8,
    status: 'Completed',
    createdAtUtc: DateTime.utc(2026, 8, 19, 7),
    readyAtUtc: null,
    handledAtUtc: null,
    locationText: '',
    onBehalfOfName: null,
    notes: '',
    lines: const [],
  ),
];

Widget _wrap(Widget home, double scale, Locale locale) => ProviderScope(
  overrides: [
    catalogueProvider.overrideWith((r) async => _cat),
    // A long, mixed-script name — the shape the server actually composes when
    // the user does not name one. It is the string that has to wrap at 320dp.
    favouritesProvider.overrideWith(
      (r) async => FavouritesResponse(
        favourites: [
          FavouriteDto(
            favouriteId: 1,
            name: 'قهوة تركي سادة (بدون سكر) + حليب، شاي بالنعناع (١ سكر)',
            createdAtUtc: DateTime.utc(2026, 8, 24),
            lastUsedAtUtc: null,
            lines: const [],
          ),
        ],
      ),
    ),
    canOrderForGuestsProvider.overrideWith((r) => true),
    myOrdersProvider.overrideWith((r) async => _orders),
    myMaterialsProvider.overrideWith((r) async => _materials),
    notificationsProvider.overrideWith((r) async => _notifications),
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
    builder: (c, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: scale,
      maxScaleFactor: scale,
      child: child!,
    ),
    home: home,
  ),
);

final _staffOrder = StaffOrderDto(
  orderId: 41,
  status: 'Pending',
  createdAtUtc: DateTime.utc(2026, 8, 20, 7),
  readyAtUtc: null,
  requesterDisplayName: 'سارة عبد الرحمن',
  department: 'الشؤون المالية والإدارية',
  locationText: 'الدور الثالث، مكتب ٣١٢',
  onBehalfOfName: 'وفد وزارة الاتصالات',
  notes: 'بدون لبن من فضلك',
  waitingSeconds: 420,
  lines: const [
    StaffOrderLineDto(
      drinkItemId: 1,
      drinkNameAr: 'قهوة تركي سادة',
      variantNameAr: 'غامق',
      sugarSpoons: 2,
      sugarNameAr: null,
      extraNamesAr: ['حليب'],
      lineNote: 'كوب كبير',
      drinkSourceOwnerName: 'سارة',
      sugarSourceOwnerName: '',
      extraSources: [],
    ),
  ],
);

/// Serves one order at a chosen status, so the status screen can be rendered
/// without a network. A worst-case order: a guest with a long name, a note and
/// a location that all have to share a 320dp width.
class _StatusRepo implements OrderRepository {
  _StatusRepo(this.status);

  final String status;

  @override
  Future<OrderSummaryDto> fetchOrder({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async => OrderSummaryDto(
    orderId: orderId,
    status: status,
    createdAtUtc: DateTime.utc(2026, 8, 20, 7),
    readyAtUtc: DateTime.utc(2026, 8, 20, 7, 5),
    handledAtUtc: null,
    locationText: 'الدور الثالث، مكتب ٣١٢',
    onBehalfOfName: 'وفد وزارة الاتصالات',
    notes: 'بدون لبن من فضلك',
    lines: const [
      OrderLineDto(
        drinkItemId: 1,
        drinkNameAr: 'قهوة تركي سادة',
        sugarSpoons: 2,
        variantId: null,
        sugarItemId: null,
        extraItemIds: [],
        lineNote: null,
        drinkFromOwn: true,
        sugarFromOwn: false,
        ownExtraItemIds: [],
      ),
    ],
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The status screen calls `context.canPop()`, which needs a router above it.
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

/// Worst-case materials: a long Arabic name beside a negative, fractional
/// balance in an admin-entered unit. The balance is allowed to go negative —
/// shortages never block serving — so this is a real row, not a contrived one.
final _materials = [
  const MyMaterialDto(
    itemId: 1,
    nameAr: 'قهوة تركي محوجة درجة أولى',
    unit: 'جرام',
    quantity: -250.5,
    servingsLeft: 0,
    level: 'Out',
    imageUrl: null,
  ),
];

final _notifications = [
  NotificationDto(
    notificationId: 1,
    kind: 'OrderReady',
    message: 'مشروبك رقم ٤١ جاهز للاستلام من البوفيه في الدور الثالث',
    orderId: 41,
    createdAtUtc: DateTime.utc(2026, 8, 20, 7),
    isRead: false,
  ),
];

void main() {
  final screens = <String, Widget>{
    'home': const HomeScreen(),
    'composer-self': const ComposerScreen(),
    'composer-guest': const ComposerScreen(
      seed: ComposerSeed(mode: OrderMode.guest),
    ),
    'my-orders': const MyOrdersScreen(),
    // Carries a two-segment language control whose labels are in different
    // scripts and cannot be shortened — the shape that has overflowed here
    // before.
    'login': const LoginScreen(),
    // Full-width cards carrying a long server-composed name plus the
    // unavailable mark — the widest thing a favourite ever renders.
    'favourites': const FavouritesScreen(),
    'settings': const SettingsScreen(),
    'materials': const MyMaterialsScreen(),
    'notifications': const NotificationsScreen(),
    // The busiest screen in the app, with a worst-case card: long names, a
    // guest, a note and a preparation. Its drink-name row was unbounded and
    // ran 210dp off a 320dp card at 2x.
    'staff-queue-card': SingleChildScrollView(
      child: QueueCard(
        order: _staffOrder,
        warnings: null,
        onMarkReady: (o, {required deliverNow}) async {},
        onComplete: null,
        onCancel: (o) async {},
      ),
    ),
  };

  for (final entry in screens.entries) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final locale in [const Locale('ar'), const Locale('en')]) {
        testWidgets('${entry.key} fits a 320dp phone at ${scale}x '
            'in ${locale.languageCode}', (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(_wrap(entry.value, scale, locale));
          // Enough pumps for the providers to deliver and the list to build.
          // NOT pumpAndSettle: a screen carrying an Image.network never
          // settles under test. Two frames were not enough — the materials
          // list had not built its rows yet, so the check passed by measuring
          // an empty screen.
          for (var i = 0; i < 8; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          // A screen still spinning has no layout to check, and an overflow
          // test that measures a spinner passes for the wrong reason — which
          // this one silently did until a provider override was found missing.
          // Fail loudly instead.
          expect(
            find.byType(CircularProgressIndicator),
            findsNothing,
            reason:
                '${entry.key} never finished loading, so nothing was measured',
          );

          // A RenderFlex overflow surfaces as a test exception. Every one of
          // these combinations used to raise one somewhere.
          expect(
            t.takeException(),
            isNull,
            reason:
                '${entry.key} overflows at ${scale}x in ${locale.languageCode}',
          );
        });
      }
    }
  }

  // The status screen gets its own group: it needs a repository override, and
  // its four-step track and guest chip are exactly the kind of thing that
  // overflows. The track was four fixed 72dp columns; the chip was an
  // unbounded row.
  for (final status in [
    'Pending',
    'InProgress',
    'Ready',
    'Completed',
    'Cancelled',
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('order status $status fits 320dp at ${scale}x', (t) async {
        t.view.physicalSize = const Size(320, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);

        await t.pumpWidget(
          ProviderScope(
            overrides: [
              orderRepositoryProvider.overrideWithValue(_StatusRepo(status)),
              catalogueProvider.overrideWith((r) async => _cat),
            ],
            child: MaterialApp(
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (c, child) => MediaQuery.withClampedTextScaling(
                minScaleFactor: scale,
                maxScaleFactor: scale,
                child: child!,
              ),
              home: const _RoutedStatus(),
            ),
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 50));

        expect(
          t.takeException(),
          isNull,
          reason: 'order status $status overflows at ${scale}x',
        );
      });
    }
  }
}
