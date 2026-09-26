@TestOn('vm')
library;

/// Renders every screen and state in the app to a PNG, for design review.
///
/// This is a **capture harness, not a golden test**: it asserts nothing about
/// pixels, so it can never fail because a colour changed. What it does assert is
/// that the screen actually rendered — a blank or still-spinning capture is
/// worse than none, because it looks like a design.
///
/// Run it with:
///
///     C:/src/flutter/bin/flutter.bat test test/screenshots --update-goldens
///
/// **The `--update-goldens` flag is required** — it is what writes the files.
/// Under a plain `flutter test` these cases still run, and still fail if a
/// screen throws or never loads, but write and compare nothing: several
/// captures are of live states (the undo countdown reads a different second
/// every run), so a pixel comparison would fail for a reason that says nothing
/// about the app.
///
/// Files land in `test/screenshots/out/` numbered in the order a reviewer
/// should walk them: the employee journey first, then staff, then the states
/// that sit off the happy path. Both locales for every screen, because Arabic
/// is the primary locale and English is a first-class second — the two wrap
/// differently and a layout approved in one can be broken in the other.
import 'package:buffet_app/app/employee_shell.dart';
import 'package:buffet_app/app/locale_controller.dart';
import 'package:buffet_app/app/routes.dart';
import 'package:buffet_app/data/api/api_client.dart';
import 'package:buffet_app/data/local/biometric_enrolment_guard.dart';
import 'package:buffet_app/data/local/biometric_service.dart';
import 'package:buffet_app/data/local/preferences_store.dart';
import 'package:buffet_app/data/local/secure_token_store.dart';
import 'package:buffet_app/data/models/favourite_models.dart';
import 'package:buffet_app/data/models/material_models.dart';
import 'package:buffet_app/data/models/order_models.dart';
import 'package:buffet_app/data/models/staff_models.dart';
import 'package:buffet_app/data/repositories/auth_repository.dart';
import 'package:buffet_app/data/repositories/materials_repository.dart';
import 'package:buffet_app/data/repositories/order_repository.dart';
import 'package:buffet_app/data/repositories/queue_repository.dart';
import 'package:buffet_app/features/auth/auth_controller.dart';
import 'package:buffet_app/features/auth/change_password_screen.dart';
import 'package:buffet_app/features/auth/lock_screen.dart';
import 'package:buffet_app/features/auth/login_screen.dart';
import 'package:buffet_app/features/auth/splash_screen.dart';
import 'package:buffet_app/features/home/home_screen.dart';
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
import 'package:buffet_app/features/staff_queue/queue_screen.dart';
import 'package:buffet_app/l10n/app_localizations.dart';
import 'package:buffet_app/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../helpers/app_harness.dart';
import 'fixtures.dart' as fx;

/// A 390x844 logical phone — an iPhone 14 / Pixel-class viewport, which is what
/// a designer reviews on. The 320dp floor is the responsive suite's job, not
/// this one's.
const _phone = Size(390, 844);

/// Serves one order at a chosen status so the status screen renders offline.
class _StatusRepo implements OrderRepository {
  _StatusRepo(this.status, {this.onBehalfOfName, this.notes = ''});

  final String status;
  final String? onBehalfOfName;
  final String notes;

  @override
  Future<OrderSummaryDto> fetchOrder({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async => fx.order(
    orderId,
    status,
    onBehalfOfName: onBehalfOfName,
    notes: notes,
    // Each time only once its step has happened, as the server sends them:
    // a Ready time on a Pending order showed a time that had not occurred.
    readyAtUtc: const {'Ready', 'Completed'}.contains(status)
        ? DateTime.utc(2026, 9, 19, 7, 6)
        : null,
    handledAtUtc: const {'Completed', 'Cancelled'}.contains(status)
        ? DateTime.utc(2026, 9, 19, 7, 11)
        : null,
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Answers the queue screen's two fetches from fixtures, and reports a shortage
/// on serving so the `200`-with-warnings card can be captured.
class _FakeQueueRepository extends QueueRepository {
  _FakeQueueRepository({
    this.queue = const [],
    this.handovers = const [],
    this.warnOnServe = false,
  }) : super(Dio());

  List<StaffOrderDto> queue;
  List<StaffOrderDto> handovers;
  final bool warnOnServe;

  @override
  Future<List<StaffOrderDto>> fetchQueue({
    required String languageCode,
    required String networkErrorFallback,
  }) async => queue;

  @override
  Future<List<StaffOrderDto>> fetchReadyForHandover({
    required String languageCode,
    required String networkErrorFallback,
  }) async => handovers;

  @override
  Future<ServeResultDto> markReady({
    required int orderId,
    required bool deliverNow,
    required String languageCode,
    required String networkErrorFallback,
  }) async {
    // Mirror the server: `/ready` takes the order out of the work queue, and
    // one NOT delivered on the spot turns up in the handover list instead.
    final served = queue.where((o) => o.orderId == orderId).toList();
    queue = queue.where((o) => o.orderId != orderId).toList();
    if (!deliverNow && served.isNotEmpty) {
      handovers = [
        for (final o in served)
          fx.staffOrder(
            o.orderId,
            status: 'Ready',
            requester: o.requesterDisplayName,
            department: o.department,
            onBehalfOfName: o.onBehalfOfName,
            notes: o.notes,
            lines: o.lines,
            readyAtUtc: DateTime.utc(2026, 9, 19, 7, 6),
          ),
        ...handovers,
      ];
    }
    return ServeResultDto(
      orderId: orderId,
      status: 'Ready',
      // A shortage is success with warnings — the drink was made.
      warnings: warnOnServe ? fx.shortageWarnings : const [],
    );
  }

  @override
  Future<void> complete({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {}

  @override
  Future<void> start({
    required int orderId,
    required String languageCode,
    required String networkErrorFallback,
  }) async {}

  @override
  Future<void> cancel({
    required int orderId,
    required String? reason,
    required String languageCode,
    required String networkErrorFallback,
  }) async {}
}

/// A biometric authenticator that is never actually consulted — the controller
/// below stubs `unlock` — but has to exist to build the real one.
class _InertAuthenticator implements BiometricAuthenticator {
  const _InertAuthenticator();

  @override
  Future<bool> canCheckBiometrics() async => true;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> availableBiometrics() async => const [];

  @override
  Future<bool> authenticate({required String localizedReason}) async => false;
}

/// Holds the auth machine at a chosen stage without touching secure storage or
/// the biometric hardware.
class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthState initial, {this.pinned = false})
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

  /// Holds [state] exactly as given. The controller restores from secure
  /// storage on construction, and storage is mocked here, so without this the
  /// restore lands a moment later and replaces a signed-in identity with an
  /// empty session.
  final bool pinned;

  @override
  set state(AuthState value) {
    if (pinned && mounted && super.state.stage != AuthStage.restoring) return;
    super.state = value;
  }

  /// The lock screen prompts on arrival. Report a plain cancellation so the
  /// screen settles into its "unlock failed, here is the way past" state
  /// rather than waiting on a platform channel that does not exist under test.
  @override
  Future<BiometricFailure?> unlock({required String reason}) async =>
      BiometricFailure.cancelled;
}

/// Serves the declare sheet's material list.
class _FakeMaterialsRepository extends MaterialsRepository {
  _FakeMaterialsRepository() : super(Dio());

  @override
  Future<List<MyMaterialDto>> fetchMine({
    required String languageCode,
    required String networkErrorFallback,
  }) async => fx.materials;
}

/// The status screen calls `context.canPop()`, so it needs a router above it.
class _Routed extends StatelessWidget {
  const _Routed(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Router.withConfig(
    config: GoRouter(
      routes: [GoRoute(path: '/', builder: (c, s) => child)],
    ),
  );
}

Widget _app(
  Widget home, {
  required Locale locale,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    // The app's own language setting, matched to the capture's locale. Some
    // screens format dates from it rather than from the MaterialApp, so
    // without this every English capture showed Arabic dates.
    localeControllerProvider.overrideWith((r) => _FixedLocale(locale)),
    catalogueProvider.overrideWith((r) async => fx.catalogue),
    favouritesProvider.overrideWith(
      (r) async => FavouritesResponse(favourites: fx.favourites),
    ),
    canOrderForGuestsProvider.overrideWith((r) => true),
    myOrdersProvider.overrideWith((r) async => fx.orders),
    myMaterialsProvider.overrideWith((r) async => fx.materials),
    notificationsProvider.overrideWith((r) async => fx.notifications),
    ...overrides,
  ],
  child: MaterialApp(
    // The real theme, so the captures show the shipped palette and type.
    theme: AppTheme.forLocale(locale),
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  ),
);

/// The employee shell on [tab], with the real tab screens behind it.
///
/// A nested Router inside the harness's MaterialApp: the shell needs
/// go_router's StatefulShellRoute, and the harness pumps a plain `home:`.
Widget _shell(String tab) => Router.withConfig(
  config: GoRouter(
    initialLocation: tab,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => EmployeeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: Routes.home, builder: (c, s) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.favourites,
                builder: (c, s) => const FavouritesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.myOrders,
                builder: (c, s) => const MyOrdersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.account,
                builder: (c, s) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  ),
);

/// One captured scenario.
class _Shot {
  const _Shot(
    this.name,
    this.build, {
    this.overrides = const [],
    this.after,
    this.height,
  });

  /// `NN-role-screen-state`, so the output directory reads as a running order.
  final String name;
  final Widget Function() build;
  final List<Override> overrides;

  /// Drives the screen into a state only reachable by interaction — tapping
  /// "serve", opening a sheet, filling a field.
  final Future<void> Function(WidgetTester)? after;

  /// A taller viewport for screens that are meant to scroll, so the reviewer
  /// sees the whole composition rather than a cropped fold.
  final double? height;
}

void main() {
  // `AuthController._restore` and `LocaleController._restore` both read secure
  // storage on construction, and there is no plugin behind the channel in a VM
  // test. Answer every call with "nothing stored", which is the cold-start
  // state these captures want anyway: signed out, and Arabic by default.
  setUpAll(() async {
    // The bundled fonts (Cairo, Inter) and the Material icons. Without them
    // every glyph renders as a tofu box: the test binding ships a placeholder
    // font with no real glyphs, which would make an Arabic-first app's
    // captures unreadable — and unreadable captures are worse than none,
    // because the layout still looks plausible.
    await loadAppFonts();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );

    // The settings screen asks whether the hardware can satisfy a prompt before
    // it draws the unlock row. Answer yes: a device that CAN is the state worth
    // reviewing, since the row is hidden entirely on one that cannot.
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/local_auth'),
      (call) async => switch (call.method) {
        'getAvailableBiometrics' => <String>['fingerprint'],
        'isDeviceSupported' || 'deviceSupportsBiometrics' => true,
        // Never reached — no capture taps the prompt — but a null here would
        // read as a silent failure rather than a decision.
        'authenticate' => false,
        _ => null,
      },
    );
  });

  final shots = <_Shot>[
    // ---------------------------------------------------------------- entry
    const _Shot('01-entry-splash', SplashScreen.new),
    const _Shot('01-entry-onboarding', OnboardingScreen.new),
    const _Shot('02-entry-login', LoginScreen.new),
    _Shot(
      '03-entry-login-session-expired',
      LoginScreen.new,
      overrides: [sessionExpiredProvider.overrideWithValue(true)],
    ),
    _Shot(
      '04-entry-lock-biometric',
      LockScreen.new,
      overrides: [
        authControllerProvider.overrideWith(
          (r) => _FakeAuthController(
            const AuthState(
              stage: AuthStage.locked,
              rememberedEmail: 'sara@buffet.test',
            ),
          ),
        ),
      ],
    ),
    // The forced first-run change: banner, no current password, no way back.
    _Shot(
      '05-entry-must-change-password',
      ChangePasswordScreen.new,
      overrides: [
        authControllerProvider.overrideWith(
          (r) => _FakeAuthController(
            const AuthState(stage: AuthStage.mustChangePassword),
            pinned: true,
          ),
        ),
      ],
    ),

    // ------------------------------------------------- employee happy path
    const _Shot('06-employee-home', HomeScreen.new, height: 1000),
    // The same screens inside the real bottom-nav shell, so the review sees
    // the chrome a user actually gets — the standalone captures omit it.
    _Shot('06-employee-shell-home', () => _shell(Routes.home)),
    _Shot(
      '06-employee-shell-account',
      () => _shell(Routes.account),
      overrides: [_signedInAs('Employee')],
    ),
    _Shot(
      '07-employee-home-no-favourites',
      HomeScreen.new,
      overrides: [
        favouritesProvider.overrideWith(
          (r) async => const FavouritesResponse(favourites: []),
        ),
      ],
      height: 1000,
    ),
    _Shot(
      '08-employee-home-no-outstanding-order',
      HomeScreen.new,
      overrides: [myOrdersProvider.overrideWith((r) async => const [])],
      height: 1000,
    ),
    const _Shot(
      '09-employee-composer-choose-drink',
      ComposerScreen.new,
      height: 1200,
    ),
    // Opened from a drink the user owns, from their own jar — so the violet
    // "made from" choice is on screen.
    _Shot(
      '10-employee-composer-drink-details',
      () => ComposerScreen(
        seed: ComposerSeed(
          drinkItemId: fx.catalogue.drinks
              .firstWhere((d) => d.hasOwnStock)
              .itemId,
          drinkFromOwn: true,
        ),
      ),
      height: 1200,
    ),
    // Opened from a favourite: straight to review.
    _Shot(
      '10-employee-composer-review',
      () =>
          ComposerScreen(seed: ComposerSeed(favourite: fx.replayableFavourite)),
      height: 1200,
    ),
    _Shot(
      '11-employee-composer-guest-mode',
      () => const ComposerScreen(seed: ComposerSeed(mode: OrderMode.guest)),
      height: 1200,
    ),
    _Shot(
      '12-employee-composer-empty-catalogue',
      ComposerScreen.new,
      overrides: [
        catalogueProvider.overrideWith((r) async => fx.emptyCatalogue),
      ],
    ),
    const _Shot('13-employee-favourites', FavouritesScreen.new, height: 1000),
    _Shot(
      '14-employee-favourites-empty',
      FavouritesScreen.new,
      overrides: [
        favouritesProvider.overrideWith(
          (r) async => const FavouritesResponse(favourites: []),
        ),
      ],
    ),

    // ------------------------------------------- employee order lifecycle
    for (final status in [
      'Pending',
      'InProgress',
      'Ready',
      'Completed',
      'Cancelled',
    ])
      _Shot(
        '15-employee-order-status-${status.toLowerCase()}',
        () => const _Routed(OrderStatusScreen(orderId: 142)),
        overrides: [
          orderRepositoryProvider.overrideWithValue(
            _StatusRepo(
              status,
              onBehalfOfName: 'وفد وزارة الاتصالات',
              notes: 'بدون لبن من فضلك',
            ),
          ),
        ],
        height: 1000,
      ),
    const _Shot('16-employee-my-orders', MyOrdersScreen.new, height: 1000),
    _Shot(
      '17-employee-my-orders-empty',
      MyOrdersScreen.new,
      overrides: [myOrdersProvider.overrideWith((r) async => const [])],
    ),

    // ------------------------------------------------- employee materials
    const _Shot('18-employee-materials', MyMaterialsScreen.new, height: 1000),
    _Shot(
      '19-employee-materials-empty',
      MyMaterialsScreen.new,
      overrides: [myMaterialsProvider.overrideWith((r) async => const [])],
    ),
    _Shot(
      '20-employee-declare-sheet',
      MyMaterialsScreen.new,
      overrides: [
        materialsRepositoryProvider.overrideWithValue(
          _FakeMaterialsRepository(),
        ),
      ],
      height: 1000,
      after: (t) async {
        final opener = find.byType(FloatingActionButton);
        if (opener.evaluate().isEmpty) return;
        await t.tap(opener.first);
        await _settle(t);
      },
    ),

    // ------------------------------------------------------ shared chrome
    const _Shot(
      '21-shared-notifications',
      NotificationsScreen.new,
      height: 1000,
    ),
    _Shot(
      '22-shared-notifications-empty',
      NotificationsScreen.new,
      overrides: [notificationsProvider.overrideWith((r) async => const [])],
    ),
    _Shot(
      '23-shared-settings',
      SettingsScreen.new,
      height: 1000,
      overrides: [_signedInAs('Employee')],
    ),
    // The voluntary change, from the account: asks the current password.
    _Shot(
      '23-shared-change-password',
      ChangePasswordScreen.new,
      overrides: [_signedInAs('Employee')],
    ),
    // Staff reach the same screen pushed from the queue: no My materials.
    _Shot(
      '23-staff-settings',
      SettingsScreen.new,
      height: 1000,
      overrides: [_signedInAs('Staff')],
    ),

    // --------------------------------------------------------- staff view
    _Shot(
      '24-staff-queue',
      QueueScreen.new,
      overrides: [
        queueRepositoryProvider.overrideWithValue(
          _FakeQueueRepository(
            queue: fx.staffQueue,
            handovers: fx.staffHandovers,
          ),
        ),
      ],
      height: 1200,
    ),
    _Shot(
      '25-staff-queue-empty',
      QueueScreen.new,
      overrides: [
        queueRepositoryProvider.overrideWithValue(_FakeQueueRepository()),
      ],
    ),
    _Shot(
      '26-staff-queue-undo-window',
      QueueScreen.new,
      overrides: [
        queueRepositoryProvider.overrideWithValue(
          _FakeQueueRepository(
            queue: fx.staffQueue,
            handovers: fx.staffHandovers,
          ),
        ),
      ],
      height: 1200,
      // The undo affordance lives ON the card, not in a SnackBar — capture it
      // so the designer reviews the thing that actually ships.
      //
      // The primary serve action is "ready and delivered", a FilledButton.
      after: (t) async {
        final serve = find.byType(FilledButton);
        if (serve.evaluate().isEmpty) return;
        await t.tap(serve.first, warnIfMissed: false);
        // Two pumps, not one: the first commits the state change, the second
        // lets the card's pending/undo subtree mount and its countdown draw.
        await t.pump();
        await t.pump(const Duration(milliseconds: 200));
      },
    ),
    _Shot(
      '27-staff-queue-shortage-warning',
      QueueScreen.new,
      overrides: [
        queueRepositoryProvider.overrideWithValue(
          _FakeQueueRepository(
            queue: fx.staffQueue,
            handovers: fx.staffHandovers,
            warnOnServe: true,
          ),
        ),
      ],
      height: 1200,
      // The rule most likely to be designed wrong: a shortage comes back as
      // `200` with warnings and the drink WAS made. It must read as
      // information, never as a failure, and it never disables a control.
      after: (t) async {
        // "Ready" (the OutlinedButton), NOT "ready and delivered": a delivered
        // order leaves the queue entirely, and the warnings are rendered on
        // the order's card — so the one that keeps a card is the one that can
        // show them. This order becomes Ready and moves to the handover tab.
        final markReady = find.byType(OutlinedButton);
        if (markReady.evaluate().isEmpty) return;
        await t.tap(markReady.first, warnIfMissed: false);
        await t.pump();
        // Past the undo window, so the call actually goes and the warnings
        // come back.
        await t.pump(const Duration(seconds: 6));
        await _settle(t);

        final tabs = find.byType(Tab);
        if (tabs.evaluate().length < 2) return;
        await t.tap(tabs.at(1));
        await _settle(t);
      },
    ),
    _Shot(
      '28-staff-handover-list',
      QueueScreen.new,
      overrides: [
        queueRepositoryProvider.overrideWithValue(
          _FakeQueueRepository(
            queue: fx.staffQueue,
            handovers: fx.staffHandovers,
          ),
        ),
      ],
      height: 1200,
      after: (t) async {
        // The second tab: `GET /staff/queue` excludes Ready, so handovers are
        // their own fetch and their own list.
        final tabs = find.byType(Tab);
        if (tabs.evaluate().length < 2) return;
        await t.tap(tabs.at(1));
        await _settle(t);
      },
    ),
    _Shot(
      '29-staff-composer-self-order',
      ComposerScreen.new,
      height: 1200,
      overrides: [canOrderForGuestsProvider.overrideWithValue(false)],
    ),
  ];

  for (final shot in shots) {
    for (final locale in [const Locale('ar'), const Locale('en')]) {
      testWidgets('${shot.name} (${locale.languageCode})', (t) async {
        t.view.physicalSize = Size(_phone.width, shot.height ?? _phone.height);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);

        await t.pumpWidget(
          _app(shot.build(), locale: locale, overrides: shot.overrides),
        );
        // Asset images decode off the fake clock, so a frame count alone can
        // leave the logo blank: the queue's top bar captured empty that way.
        // Decode it for real before settling, so every shot shows it.
        await t.runAsync(
          () => precacheImage(
            const AssetImage('assets/images/logo-defi.png'),
            t.element(find.byType(MaterialApp)),
          ),
        );
        await _settle(t);
        if (shot.after != null) await shot.after!(t);

        // A capture of a spinner or a stack trace looks like a design decision
        // to whoever opens the folder. Fail instead of shipping one.
        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: '${shot.name} never finished loading',
        );
        expect(
          t.takeException(),
          isNull,
          reason: '${shot.name} threw while rendering',
        );

        // Writing the PNG is the point of this file; COMPARING against a
        // stored one is not, and must not happen on an ordinary `flutter
        // test`. Several captures are of live, moving states — the undo
        // countdown reads a different second on every run — so a pixel
        // comparison would fail for a reason that says nothing about the app.
        //
        // `autoUpdateGoldenFiles` is true exactly under `--update-goldens`,
        // which is how this harness is meant to be run.
        if (autoUpdateGoldenFiles) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('out/${shot.name}-${locale.languageCode}.png'),
          );
        }
      });
    }
  }
}

/// Enough frames for providers to deliver and lists to build.
///
/// NOT `pumpAndSettle`: a screen carrying an `Image.network` or a polling timer
/// never settles, and the queue screen has both.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// A signed-in session with a name and department, so the account header is
/// in the capture.
Override _signedInAs(String role) => authControllerProvider.overrideWith(
  (r) => _FakeAuthController(
    AuthState(
      stage: AuthStage.signedIn,
      restoredIdentity: (
        role: role,
        displayName: 'سارة أحمد',
        department: 'الشؤون المالية',
        canOrderForGuests: false,
      ),
    ),
    pinned: true,
  ),
);

/// The language setting held at one locale, as the user would have chosen it.
class _FixedLocale extends LocaleController {
  _FixedLocale(Locale locale)
    : super(const PreferencesStore(FlutterSecureStorage())) {
    state = locale;
  }
}
