import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/api/api_config.dart';
import '../../data/local/order_alerts.dart';
import '../../data/models/catalogue_models.dart';
import '../../data/models/favourite_models.dart';
import '../../data/models/order_models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/error_text.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/brand_lockup.dart';
import '../../shared/widgets/notification_bell.dart';
import '../../shared/widgets/search_field.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../auth/auth_controller.dart';
import '../notifications/notifications_screen.dart';
import '../order/composer_screen.dart';
import '../order/favourites_controller.dart';
import '../order/favourites_screen.dart';
import '../order/my_orders_screen.dart';
import '../order/order_mode.dart';
import '../order/order_status_tracker.dart';
import '../order/widgets/drink_menu.dart';
import '../order/widgets/favourites_strip.dart';
import '../order/widgets/outstanding_order_card.dart';

/// The employee's landing screen: the Home tab of the shell.
///
/// The design's Home: a greeting, drink search, the outstanding order when
/// there is one, the user's favourites, and the menu — every drink, grouped
/// by the jar it would be made from («من موادي» first, guide §7.1). Tapping a
/// drink opens the composer with it already chosen; tapping a favourite fills
/// the composer from it. Nothing here places an order outright.
///
/// It also keeps three jobs from when the composer was the landing screen:
/// keeping the outstanding-order card fresh, asking for notification
/// permission once the user has seen what the app does, and reporting a
/// session that failed to refresh after a password change.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  /// Announces an order turning Ready or Cancelled, from every look at the
  /// list: this screen's poll, a pull-to-refresh, and the tracking screen's
  /// own refreshes, which reload the list when they see a change. Home stays
  /// mounted beneath every tab and pushed screen, so this is the one place
  /// that sees every order while the app is in the foreground.
  final _tracker = OrderStatusTracker();

  Timer? _pollTimer;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
    // Channels and the permission prompt, once the user is signed in and has
    // seen what the app does — never at startup, which is how a permission
    // gets denied permanently.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(prepareOrderAlerts(context, ref));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // A drink can turn Ready while the app is in the background. Re-reading
      // on resume is what makes the card honest for the user who closed the
      // app to wait — the case this whole card is for.
      case AppLifecycleState.resumed:
        // Forgotten again here, not only on leaving: a load still in flight
        // when the phone was locked lands in the background and would become
        // the baseline, and the reload below would then announce a change
        // already on screen (and already pushed, on Android).
        _tracker.forget();
        ref
          ..invalidate(myOrdersProvider)
          // The bell's badge reads this list, and nothing else reloads it.
          ..invalidate(notificationsProvider);
        _startPolling();
      case AppLifecycleState.inactive:
        _pollTimer?.cancel();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _pollTimer?.cancel();
        // A change found on return is on screen; a push has announced it.
        _tracker.forget();
    }
  }

  /// Keeps the outstanding-order card fresh while this screen is open.
  ///
  /// Uses the order poll interval rather than the queue's: this is one person's
  /// drink, not a shared work queue.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      ApiConfig.orderPollInterval,
      // The notifications ride along, so a declaration confirmed while the
      // app is open reaches the bell's badge.
      (_) => ref
        ..invalidate(myOrdersProvider)
        ..invalidate(notificationsProvider),
    );
  }

  void _openComposer({
    required OrderMode mode,
    FavouriteDto? favourite,
    CatalogueItemDto? drink,
    bool fromOwn = false,
  }) {
    unawaited(
      context.push(
        Routes.catalogue,
        extra: ComposerSeed(
          mode: mode,
          favourite: favourite,
          drinkItemId: drink?.itemId,
          drinkFromOwn: fromOwn,
        ),
      ),
    );
  }

  /// "Good morning, Sara" — the first name only, as the design greets. The
  /// hour is the device's local time.
  String _greeting(AppLocalizations l10n) {
    final name = ref
        .watch(authControllerProvider)
        .displayName
        ?.trim()
        .split(RegExp(r'\s+'))
        .first;
    if (name == null || name.isEmpty) return l10n.greetingNoName;
    final hour = DateTime.now().hour;
    if (hour < 12) return l10n.greetingMorning(name);
    if (hour < 17) return l10n.greetingAfternoon(name);
    return l10n.greetingEvening(name);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<OrderSummaryDto>>>(myOrdersProvider, (_, next) {
      // Settled data only. A refresh passes through loading (and a failed one
      // through error) still carrying the previous list, and a stale list
      // taken as the first look after a return would announce what the user
      // is already looking at.
      // (Riverpod marks a refresh as data with isLoading set, so both.)
      if (next is! AsyncData<List<OrderSummaryDto>> || next.isLoading) return;
      final orders = next.value;
      final alerts = ref.read(orderAlertsProvider);
      final l10n = AppLocalizations.of(context);
      for (final order in _tracker.changed(orders)) {
        announceOrderChange(alerts, l10n, order);
      }
    });
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final outstanding = ref.watch(outstandingOrdersProvider);
    // valueOrNull, not `when`: the rest of Home must never wait on the
    // favourites list, and an empty strip is the same shape as one that has
    // not loaded.
    final favourites =
        ref.watch(favouritesProvider).valueOrNull?.favourites ?? const [];
    final catalogue = ref.watch(catalogueProvider);
    // Null while the catalogue loads: a favourite renders as available until
    // the catalogue says otherwise, rather than the strip flashing
    // "unavailable" over a request that has not come back yet.
    final availableItemIds = catalogue.valueOrNull?.drinks
        .map((d) => d.itemId)
        .toSet();
    final canOrderForGuests = ref.watch(canOrderForGuestsProvider);
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        // The design's top bar: the lockup at the start, the bell at the end.
        // The lockup is decorative, so the bar carries the app's name for
        // screen readers.
        title: Semantics(
          header: true,
          label: l10n.homeTitle,
          child: const BrandLockup(width: 120),
        ),
        // The bell only. Settings is the Account tab and My orders the Orders
        // tab — a control here for either would be the same destination twice
        // on one screen.
        actions: const [NotificationBell()],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(myOrdersProvider)
            ..invalidate(catalogueProvider)
            ..invalidate(favouritesProvider)
            ..invalidate(notificationsProvider);
        },
        // A Column in a scroll view, not a ListView: the jump chips scroll to a
        // section heading, and a lazy list does not build a heading that is
        // off screen — the chip would silently do nothing. The menu is tens of
        // drinks, not thousands, so building it all costs nothing.
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Dimens.gutter,
            vertical: Dimens.space5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The password change worked but the token refresh did not.
              // Shown here because this is where the user lands afterwards.
              if (ref.watch(sessionNotRefreshedProvider)) ...[
                InlineBanner(
                  tone: BannerTone.warning,
                  title: l10n.sessionNotRefreshed,
                ),
                const SizedBox(height: Dimens.space4),
              ],

              Text(
                _greeting(l10n),
                style: text.headlineSmall?.copyWith(color: BrandColors.brand),
              ),
              const SizedBox(height: Dimens.space4),

              // The first way into ordering, so it sits above everything that
              // can grow — the owed-order card, the favourites.
              SearchField(
                controller: _search,
                hint: l10n.searchDrinksHint,
                clearTooltip: l10n.clearSearch,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: Dimens.space5),

              // A drink already owed to the user outranks placing another.
              // Closing the app while waiting is normal, and on the next launch
              // this screen is where they land.
              if (outstanding.isNotEmpty) ...[
                OutstandingOrderCard(
                  order: outstanding.first,
                  othersCount: outstanding.length - 1,
                  onTap: () => context.push(
                    Routes.orderStatusFor(outstanding.first.orderId),
                  ),
                ),
                const SizedBox(height: Dimens.space5),
              ],

              // One tap from launch to the same coffee as yesterday — for an
              // order the user chose to keep, not one guessed from their last.
              // Seeds the composer rather than placing outright. Hidden while
              // searching: the results are what the user asked for.
              //
              // Four at most, and no "show all" link: the Favourites tab is
              // that destination, already on screen in the bar below.
              if (favourites.isNotEmpty && !searching) ...[
                FavouritesStrip(
                  favourites: favourites,
                  availableItemIds: availableItemIds,
                  onReplay: (favourite) =>
                      _openComposer(mode: OrderMode.self, favourite: favourite),
                  onDelete: (favourite) => unawaited(
                    confirmDeleteFavourite(context, ref, favourite),
                  ),
                  restReachableElsewhere: true,
                ),
                const SizedBox(height: Dimens.space5),
              ],

              // Shown only when the token carries the privilege. The server
              // reads it from the token's claims, not the body — a client
              // cannot grant itself this, and offering it to someone without it
              // would produce an unexplained rejection. Brand, never violet: a
              // guest order is if anything the opposite of "my own jar".
              if (canOrderForGuests && !searching) ...[
                OutlinedButton.icon(
                  onPressed: () => _openComposer(mode: OrderMode.guest),
                  icon: const Icon(Icons.person_add_alt_outlined),
                  label: Text(l10n.orderForGuest),
                ),
                const SizedBox(height: Dimens.space5),
              ],

              ...catalogue.when(
                loading: () => const [
                  Padding(
                    padding: EdgeInsetsDirectional.all(Dimens.space6),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (error, _) => [
                  EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: l10n.genericError,
                    body: describeError(error, l10n),
                    action: OutlinedButton.icon(
                      onPressed: () => ref.invalidate(catalogueProvider),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  ),
                ],
                data: (data) => [
                  if (data.drinks.isEmpty)
                    EmptyState(
                      icon: Icons.no_drinks_outlined,
                      title: l10n.emptyCatalogueTitle,
                      body: l10n.emptyCatalogueBody,
                    )
                  else
                    // The same menu the composer's first step shows, so the two never
                    // list drinks differently.
                    DrinkMenu(
                      drinks: data.drinks,
                      query: _query,
                      onSelect: (drink, {required fromOwn}) => _openComposer(
                        mode: OrderMode.self,
                        drink: drink,
                        fromOwn: fromOwn,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
