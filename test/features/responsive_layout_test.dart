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
import 'package:buffet_app/app/employee_shell.dart';
import 'package:buffet_app/app/routes.dart';
import 'package:buffet_app/data/models/catalogue_models.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/material_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:buffet_app/data/repositories/order_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/auth/change_password_screen.dart';
import 'package:buffet_app/features/auth/lock_screen.dart';
import 'package:buffet_app/features/auth/login_screen.dart';
import 'package:buffet_app/features/auth/splash_screen.dart';
import 'package:buffet_app/features/home/home_screen.dart';
import 'package:buffet_app/features/materials/declare_sheet.dart';
import 'package:buffet_app/features/materials/my_materials_screen.dart';
import 'package:buffet_app/features/notifications/notifications_screen.dart';
import 'package:buffet_app/features/onboarding/onboarding_screen.dart';
import 'package:buffet_app/features/order/composer_screen.dart';
import 'package:buffet_app/features/order/favourites_controller.dart';
import 'package:buffet_app/features/order/favourites_screen.dart';
import 'package:buffet_app/features/order/my_orders_screen.dart';
import 'package:buffet_app/features/order/order_mode.dart';
import 'package:buffet_app/features/order/order_status_screen.dart';
import 'package:buffet_app/features/settings/settings_screen.dart';
import 'package:buffet_app/features/staff_queue/widgets/queue_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_auth_controller.dart';

/// An extra, for the composer's widest rows.
CatalogueItemDto _e(int id, String n, {int own = 0}) => CatalogueItemDto(
  itemId: id,
  nameAr: n,
  nameEn: n,
  category: 'Extra',
  unit: 'ج',
  imageUrl: null,
  inStock: true,
  hasOwnStock: own > 0,
  ownServingsLeft: own,
  variants: const [],
  allowedExtraItemIds: null,
);

/// The widest menu the composer draws: an out-of-stock drink (its badge), a
/// drink made two ways whose preparation pours an extra (the double-portion
/// mark), and three extras, one the user owns. Long descriptions and menu
/// groups (§7.9), including a drink with no group, so the chip row carries
/// Other too.
final _cat = CatalogueResponse(
  drinks: [
    const CatalogueItemDto(
      itemId: 1,
      nameAr: 'قهوة تركي سادة',
      nameEn: 'قهوة تركي سادة',
      category: 'Drink',
      unit: 'ج',
      imageUrl: null,
      inStock: false,
      hasOwnStock: false,
      ownServingsLeft: 0,
      variants: [],
      allowedExtraItemIds: null,
      descriptionAr:
          'قهوة تركية محوّجة بالهيل، تُحضّر على نار هادئة وتُقدّم مع كوب ماء '
          'بارد، كما يحبها الجميع في المكتب منذ الصباح الباكر',
      drinkGroupId: 1,
    ),
    const CatalogueItemDto(
      itemId: 2,
      nameAr: 'شاي بالنعناع',
      nameEn: 'شاي بالنعناع',
      category: 'Drink',
      unit: 'ج',
      imageUrl: null,
      inStock: true,
      hasOwnStock: true,
      ownServingsLeft: 0,
      variants: [
        VariantDto(
          variantId: 21,
          nameAr: 'فرنساوي بالحليب كامل الدسم',
          nameEn: 'French, with full-fat milk',
          isDefault: true,
          ingredientItemIds: [10],
        ),
        VariantDto(
          variantId: 22,
          nameAr: 'غامق مع هيل مطحون',
          nameEn: 'Dark, with ground cardamom',
          isDefault: false,
        ),
      ],
      allowedExtraItemIds: null,
    ),
  ],
  sugars: const [],
  extras: [
    _e(10, 'حليب كامل الدسم', own: 4),
    _e(11, 'قرفة مطحونة'),
    _e(12, 'هيل'),
  ],
  locations: const [],
  maxLines: 5,
  maxBuffetDrinks: 1,
  drinkGroups: const [
    DrinkGroupDto(
      drinkGroupId: 1,
      nameAr: 'القهوة والمشروبات الساخنة',
      nameEn: 'Coffee and hot drinks',
      sortOrder: 1,
    ),
    DrinkGroupDto(
      drinkGroupId: 2,
      nameAr: 'العصائر الطازجة',
      nameEn: 'Fresh juices',
      sortOrder: 2,
    ),
  ],
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
    lines: const [
      OrderLineDto(
        drinkItemId: 1,
        drinkNameAr: 'قهوة تركي سادة',
        sugarSpoons: 2,
        variantId: null,
        sugarItemId: null,
        extraItemIds: [],
        lineNote: null,
        drinkFromOwn: false,
        sugarFromOwn: false,
        ownExtraItemIds: [],
      ),
      OrderLineDto(
        drinkItemId: 1,
        drinkNameAr: 'قهوة تركي سادة',
        sugarSpoons: 2,
        variantId: null,
        sugarItemId: null,
        extraItemIds: [],
        lineNote: null,
        drinkFromOwn: false,
        sugarFromOwn: false,
        ownExtraItemIds: [],
      ),
      OrderLineDto(
        drinkItemId: 2,
        drinkNameAr: 'شاي بالنعناع',
        sugarSpoons: 0,
        variantId: null,
        sugarItemId: null,
        extraItemIds: [],
        lineNote: null,
        drinkFromOwn: false,
        sugarFromOwn: false,
        ownExtraItemIds: [],
      ),
    ],
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

Widget _wrap(
  Widget home,
  double scale,
  Locale locale, [
  List<Override> extra = const [],
]) => ProviderScope(
  overrides: [
    ...extra,
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
  // The real theme and fonts: measuring Flutter's default theme with a
  // placeholder font would pass layouts the shipped app overflows.
  child: testApp(home: home, locale: locale, textScale: scale),
);

StaffOrderDto _staffOrderAt(String status) => StaffOrderDto(
  orderId: 41,
  status: status,
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
  setUpAll(loadAppFonts);

  final screens = <String, Widget>{
    'home': const HomeScreen(),
    // Home inside the real shell, so the 80dp tab bar and its labels are
    // measured too — the labels are in two scripts and cannot shorten.
    'shell-home': const _ShellHome(),
    'composer-self': const ComposerScreen(),
    'composer-guest': const ComposerScreen(
      seed: ComposerSeed(mode: OrderMode.guest),
    ),
    // The composer's later steps carry most of its controls, so each is held
    // to 320dp too. Drink Details for an owned drink whose jar reads empty:
    // the violet jar choice, the shortage banner, sugar and the stepper.
    'composer-details': const ComposerScreen(
      seed: ComposerSeed(drinkItemId: 2, drinkFromOwn: true),
    ),
    // The long description, whole, above the controls.
    'composer-details-described': const ComposerScreen(
      seed: ComposerSeed(drinkItemId: 1),
    ),
    // Review, from a favourite: grouped identical cups, a line with extras,
    // a drink no longer on the menu and one past the buffet cap (so the
    // favourite notice), with location, notes, save-as-favourite and footer.
    'composer-review': ComposerScreen(
      seed: ComposerSeed(
        favourite: FavouriteDto(
          favouriteId: 9,
          name: 'قهوة تركي سادة (بدون سكر) + حليب',
          createdAtUtc: DateTime.utc(2026, 8, 24),
          lastUsedAtUtc: null,
          lines: const [
            OrderLineDto(
              drinkItemId: 1,
              drinkNameAr: 'قهوة تركي سادة',
              sugarSpoons: 2,
              variantId: null,
              sugarItemId: null,
              extraItemIds: [11, 12],
              lineNote: null,
              drinkFromOwn: false,
              sugarFromOwn: false,
              ownExtraItemIds: [],
            ),
            OrderLineDto(
              drinkItemId: 2,
              drinkNameAr: 'شاي بالنعناع',
              sugarSpoons: 0,
              variantId: 21,
              sugarItemId: null,
              extraItemIds: [10],
              lineNote: null,
              drinkFromOwn: true,
              sugarFromOwn: false,
              ownExtraItemIds: [10],
            ),
            OrderLineDto(
              drinkItemId: 2,
              drinkNameAr: 'شاي بالنعناع',
              sugarSpoons: 0,
              variantId: 21,
              sugarItemId: null,
              extraItemIds: [10],
              lineNote: null,
              drinkFromOwn: true,
              sugarFromOwn: false,
              ownExtraItemIds: [10],
            ),
            OrderLineDto(
              drinkItemId: 99,
              drinkNameAr: 'كابتشينو بالكراميل المملح',
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
        ),
      ),
    ),
    'my-orders': const MyOrdersScreen(),
    // Carries a two-segment language control whose labels are in different
    // scripts and cannot be shortened — the shape that has overflowed here
    // before.
    'login': const LoginScreen(),
    // Both notices at once (enrolment changed, session expired), above the
    // form: the tallest the sign-in screen gets.
    'login-notices': const LoginScreen(),
    // The lock after a cancelled prompt, with its banner and a long address.
    'lock': const LockScreen(),
    // Forced: the warning banner and the Sign out exit. Voluntary: the
    // current-password field as well.
    'change-password-forced': const ChangePasswordScreen(),
    'change-password': const ChangePasswordScreen(),
    'splash': const SplashScreen(),
    // Three slides whose copy must fit a card at 2x in both scripts; the card
    // scrolls rather than overflowing.
    'onboarding': const OnboardingScreen(),
    // Full-width cards carrying a long server-composed name plus the
    // unavailable mark — the widest thing a favourite ever renders.
    'favourites': const FavouritesScreen(),
    'settings': const SettingsScreen(),
    'materials': const MyMaterialsScreen(),
    // The sheet as the materials screen opens it: its item list, quantity
    // field and hints in a sheet that has to scroll rather than overflow.
    'declare-sheet': const Scaffold(body: DeclareSheet()),
    'notifications': const NotificationsScreen(),
    // The busiest screen in the app, with a worst-case card: long names, a
    // guest, a note and a preparation. Its drink-name row was unbounded and
    // ran 210dp off a 320dp card at 2x.
    'staff-queue-card': SingleChildScrollView(
      child: QueueCard(
        order: _staffOrderAt('Pending'),
        warnings: null,
        onMarkReady: (o, {required deliverNow}) async {},
        onComplete: null,
        onCancel: (o) async {},
        onStart: (o) async {},
      ),
    ),
    // Started: the "being made" statement in the start button's place.
    'staff-queue-card-in-progress': SingleChildScrollView(
      child: QueueCard(
        order: _staffOrderAt('InProgress'),
        warnings: null,
        onMarkReady: (o, {required deliverNow}) async {},
        onComplete: null,
        onCancel: (o) async {},
        onStart: (o) async {},
      ),
    ),
  };

  // The entry screens read the auth machine; each is held at the stage that
  // draws it, without secure storage or biometric hardware.
  Override auth(AuthState state) => authControllerProvider.overrideWith(
    (r) => FakeAuthController(state, pinned: true),
  );
  final overridesFor = <String, List<Override>>{
    'login-notices': [
      authControllerProvider.overrideWith(
        (r) => FakeAuthController(
          const AuthState(
            stage: AuthStage.signedOut,
            signedOutByEnrolmentChange: true,
            sessionExpired: true,
          ),
          pinned: true,
        ),
      ),
    ],
    'lock': [
      auth(
        const AuthState(
          stage: AuthStage.locked,
          rememberedEmail: 'abdelrahman.elsayed.mahmoud@company.com',
        ),
      ),
    ],
    'change-password-forced': [
      auth(const AuthState(stage: AuthStage.mustChangePassword)),
    ],
    'change-password': [auth(const AuthState(stage: AuthStage.signedIn))],
  };

  for (final entry in screens.entries) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final locale in [const Locale('ar'), const Locale('en')]) {
        testWidgets('${entry.key} fits a 320dp phone at ${scale}x '
            'in ${locale.languageCode}', (t) async {
          t.view.physicalSize = const Size(320, 640);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            _wrap(
              entry.value,
              scale,
              locale,
              overridesFor[entry.key] ?? const [],
            ),
          );
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

          // My orders keeps its finished orders on a second tab, which the
          // first pass never builds.
          if (entry.key == 'my-orders') {
            await t.tap(find.byType(Tab).last);
            await t.pumpAndSettle();
            expect(
              t.takeException(),
              isNull,
              reason:
                  'my-orders Earlier overflows at ${scale}x in '
                  '${locale.languageCode}',
            );
          }
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
    for (final locale in const [Locale('ar'), Locale('en')]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('order status $status fits 320dp at ${scale}x in '
            '${locale.languageCode}', (t) async {
          t.view.physicalSize = const Size(320, 900);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);

          await t.pumpWidget(
            ProviderScope(
              overrides: [
                orderRepositoryProvider.overrideWithValue(_StatusRepo(status)),
                catalogueProvider.overrideWith((r) async => _cat),
              ],
              child: testApp(
                home: const _RoutedStatus(),
                textScale: scale,
                locale: locale,
              ),
            ),
          );
          await t.pump();
          await t.pump(const Duration(milliseconds: 50));

          // Never measure a spinner: that passes for the wrong reason.
          expect(
            find.byType(CircularProgressIndicator),
            findsNothing,
            reason: 'order status $status never finished loading',
          );
          expect(
            t.takeException(),
            isNull,
            reason:
                'order status $status overflows at ${scale}x in '
                '${locale.languageCode}',
          );
        });
      }
    }
  }
}

/// Home inside the real employee shell. The router is built in initState, not
/// at `main()` time: constructing a GoRouter before the test binding exists
/// initialises the wrong binding and fails the whole file on load.
class _ShellHome extends StatefulWidget {
  const _ShellHome();

  @override
  State<_ShellHome> createState() => _ShellHomeState();
}

class _ShellHomeState extends State<_ShellHome> {
  late final GoRouter _router = GoRouter(
    initialLocation: Routes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => EmployeeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.home, builder: (c, s) => const HomeScreen()),
            ],
          ),
          for (final tab in Routes.shellTabs.skip(1))
            StatefulShellBranch(
              routes: [
                GoRoute(path: tab, builder: (c, s) => const SizedBox.shrink()),
              ],
            ),
        ],
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
