import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/api/api_config.dart';
import '../../data/local/order_alerts.dart';
import '../../data/models/favourite_models.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/exit_confirmation.dart';
import '../../shared/widgets/notification_bell.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../auth/auth_controller.dart';
import '../order/composer_screen.dart';
import '../order/favourites_controller.dart';
import '../order/favourites_screen.dart';
import '../order/my_orders_screen.dart';
import '../order/order_mode.dart';
import '../order/widgets/favourites_strip.dart';
import '../order/widgets/outstanding_order_card.dart';

/// The employee's landing screen, and the answer to "what can I do from here?".
///
/// Before this existed the composer *was* the landing screen: the app opened on
/// a drink picker, and every other destination was an unlabelled icon in its
/// app bar. A user could answer "what drink do I want?" but not "what can I
/// do?".
///
/// The grid is permission-aware — the guest tile is absent, not disabled, for a
/// token without the privilege. A disabled tile would advertise a capability
/// the user cannot obtain from this screen, which is worse than silence.
///
/// This screen also inherits three jobs that belonged to the composer only
/// because the composer used to be where the user landed: keeping the
/// outstanding-order card fresh, asking for notification permission once the
/// user has seen what the app does, and reporting a session that failed to
/// refresh after a password change.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  Timer? _pollTimer;

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // A drink can turn Ready while the app is in the background. Re-reading
      // on resume is what makes the card honest for the user who closed the
      // app to wait — the case this whole card is for.
      case AppLifecycleState.resumed:
        ref.invalidate(myOrdersProvider);
        _startPolling();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _pollTimer?.cancel();
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
      (_) => ref.invalidate(myOrdersProvider),
    );
  }

  void _openComposer({required OrderMode mode, FavouriteDto? favourite}) {
    unawaited(
      context.push(
        Routes.catalogue,
        extra: ComposerSeed(mode: mode, favourite: favourite),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final outstanding = ref.watch(outstandingOrdersProvider);
    // valueOrNull, not `when`: the action grid must never wait on the
    // favourites list. A user whose network is slow can still tap New Order,
    // and an empty strip is the same shape as one that has not loaded.
    final favourites =
        ref.watch(favouritesProvider).valueOrNull?.favourites ?? const [];
    // Null while the catalogue loads: a favourite renders as available until
    // the catalogue says otherwise, rather than the strip flashing
    // "unavailable" over a request that has not come back yet.
    final availableItemIds = ref
        .watch(catalogueProvider)
        .valueOrNull
        ?.drinks
        .map((d) => d.itemId)
        .toSet();
    final canOrderForGuests = ref.watch(canOrderForGuestsProvider);

    return ExitConfirmation(
      // A landing screen: nothing sits beneath it in the stack, so back
      // would otherwise close the app outright.
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.homeTitle),
          actions: const [NotificationBell(), _SettingsAction()],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(myOrdersProvider)
              ..invalidate(catalogueProvider)
              ..invalidate(favouritesProvider);
          },
          child: ListView(
            padding: const EdgeInsetsDirectional.all(Dimens.space4),
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

              // Above everything: a drink already owed to the user outranks
              // placing another. Closing the app while waiting is normal, and
              // on the next launch this screen is where they land.
              if (outstanding.isNotEmpty) ...[
                OutstandingOrderCard(
                  order: outstanding.first,
                  othersCount: outstanding.length - 1,
                  onTap: () => context.push(
                    Routes.orderStatusFor(outstanding.first.orderId),
                  ),
                ),
                const SizedBox(height: Dimens.space4),
              ],

              // One tap from launch to the same coffee as yesterday — for an
              // order the user chose to keep, not one guessed from their last.
              // Seeds the composer rather than placing outright, so they still
              // see and confirm what they are ordering.
              //
              // Absent rather than empty when nothing is saved: a heading over
              // no cards is noise on the screen people open to order a drink.
              if (favourites.isNotEmpty) ...[
                FavouritesStrip(
                  favourites: favourites,
                  availableItemIds: availableItemIds,
                  onReplay: (favourite) =>
                      _openComposer(mode: OrderMode.self, favourite: favourite),
                  onDelete: (favourite) => unawaited(
                    confirmDeleteFavourite(context, ref, favourite),
                  ),
                  onShowAll: () => context.push(Routes.favourites),
                ),
                const SizedBox(height: Dimens.space4),
              ],

              // The primary action spans the full width: there is exactly one
              // thing most people open this app to do, and a grid that gave it
              // the same weight as "my materials" would hide it in plain sight.
              _PrimaryActionTile(
                icon: Icons.add_circle_outline,
                label: l10n.homeNewOrder,
                subtitle: l10n.homeNewOrderSubtitle,
                onTap: () => _openComposer(mode: OrderMode.self),
              ),
              const SizedBox(height: Dimens.space3),

              // Shown only when the token carries the privilege. The server
              // reads it from the token's claims, not the body — a client
              // cannot grant itself this, and offering the action to someone
              // without it would produce an unexplained rejection.
              if (canOrderForGuests) ...[
                _PrimaryActionTile(
                  icon: Icons.person_add_alt_outlined,
                  label: l10n.homeGuestOrder,
                  subtitle: l10n.homeGuestOrderSubtitle,
                  // Brand, never accent: violet means "from my own jar", and a
                  // guest order is if anything the opposite of that.
                  emphasised: false,
                  onTap: () => _openComposer(mode: OrderMode.guest),
                ),
                const SizedBox(height: Dimens.space3),
              ],

              // Notifications and settings are DELIBERATELY not here. They sit
              // in the app bar, and having them in both places put the same
              // destination on one screen twice — two controls, same icon,
              // same route, a few hundred pixels apart. The grid is for the
              // things this screen is *about*: the user's orders and their
              // materials. Chrome that follows the user between screens
              // belongs in the chrome.
              //
              // A LayoutBuilder-sized Wrap rather than a GridView: a grid's
              // childAspectRatio fixes the tile HEIGHT, so a label that needs
              // more room than the ratio allows overflows rather than growing
              // — which it did at the DEFAULT text scale on a 320dp phone,
              // and badly at the accessibility scales. Tiles now size to their
              // content and simply get taller.
              LayoutBuilder(
                builder: (context, constraints) {
                  final tileWidth = (constraints.maxWidth - Dimens.space3) / 2;
                  return Wrap(
                    spacing: Dimens.space3,
                    runSpacing: Dimens.space3,
                    children: [
                      _ActionTile(
                        width: tileWidth,
                        icon: Icons.receipt_long_outlined,
                        label: l10n.homeMyOrders,
                        onTap: () => context.push(Routes.myOrders),
                      ),
                      _ActionTile(
                        width: tileWidth,
                        icon: Icons.inventory_2_outlined,
                        label: l10n.homeMyMaterials,
                        onTap: () => context.push(Routes.materials),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pulled out so the app bar's action list can stay `const`.
class _SettingsAction extends StatelessWidget {
  const _SettingsAction();

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.settings_outlined),
    tooltip: AppLocalizations.of(context).settings,
    onPressed: () => context.push(Routes.settings),
  );
}

/// A full-width action, for the things people came here to do.
class _PrimaryActionTile extends StatelessWidget {
  const _PrimaryActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.emphasised = true,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  /// The filled treatment. Exactly one tile on the screen gets it.
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final background = emphasised ? BrandColors.brand : BrandColors.surface;
    final foreground = emphasised ? BrandColors.surface : BrandColors.brand;
    final labelColour = emphasised ? BrandColors.surface : BrandColors.ink;

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Dimens.radiusLg),
          child: Container(
            constraints: const BoxConstraints(minHeight: Dimens.minTarget),
            padding: const EdgeInsetsDirectional.all(Dimens.space4),
            decoration: BoxDecoration(
              border: Border.all(
                color: emphasised ? BrandColors.brand : BrandColors.brandLight,
              ),
              borderRadius: BorderRadius.circular(Dimens.radiusLg),
            ),
            child: Row(
              children: [
                Icon(icon, size: 28, color: foreground),
                const SizedBox(width: Dimens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: labelColour),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: emphasised
                              ? BrandColors.brandLight
                              : BrandColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One square in the secondary grid.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.width,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  /// Half the row, measured by the parent. The tile sets its own height from
  /// its content, so a long label or a large text scale makes it taller rather
  /// than overflowing it.
  final double width;

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: BrandColors.surface,
      borderRadius: BorderRadius.circular(Dimens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
        child: Container(
          width: width,
          constraints: const BoxConstraints(minHeight: Dimens.minTarget * 1.6),
          padding: const EdgeInsetsDirectional.all(Dimens.space3),
          decoration: BoxDecoration(
            border: Border.all(color: BrandColors.brandLight),
            borderRadius: BorderRadius.circular(Dimens.radiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // No badge here any more: the unread count lives on the app
              // bar's bell, which is now the only way to notifications. Two
              // counts from one provider were still two things to keep
              // agreeing for no gain.
              Icon(icon, size: 24, color: BrandColors.brand),
              const SizedBox(height: Dimens.space2),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
