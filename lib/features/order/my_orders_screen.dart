import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/catalogue_models.dart';
import '../../data/models/order_models.dart';
import '../../data/repositories/favourites_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/error_text.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import 'composer_screen.dart';
import 'favourites_controller.dart';
import 'order_drinks.dart';
import 'widgets/favourite_name_dialog.dart';

/// The caller's own orders, newest first.
final myOrdersProvider = FutureProvider.autoDispose<List<OrderSummaryDto>>((
  ref,
) async {
  final locale = ref.watch(localeControllerProvider);
  return ref
      .watch(orderRepositoryProvider)
      .fetchMyOrders(
        languageCode: locale.languageCode,
        // Never shown: screens render a network failure through describeError.
        networkErrorFallback: '',
      );
});

/// The orders that are still owed to the user — anything not [OrderStatus]
/// settled, most urgent first.
///
/// Derived from [myOrdersProvider] rather than fetching again, so the home
/// screen and the history screen can never disagree about what is outstanding.
///
/// Ready leads: a drink standing on the counter needs the user more than one
/// still being made does. Within each group the newest order comes first,
/// matching the server's ordering.
final outstandingOrdersProvider = Provider.autoDispose<List<OrderSummaryDto>>((
  ref,
) {
  final orders = ref.watch(myOrdersProvider).valueOrNull ?? const [];
  // Compared by name through OrderStatus — never by ordinal (rule 5).
  final ready = orders.where((o) => o.orderStatus == OrderStatus.ready);
  final live = orders.where((o) => o.orderStatus.isLive);
  return [...ready, ...live];
});

/// Order history — and, more importantly, the way back to a **live** order.
///
/// Without this screen the status screen was reachable only by placing an
/// order: leave it and a drink still being made became untraceable. Live
/// orders are listed first and separately for exactly that reason.
class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final orders = ref.watch(myOrdersProvider);
    // valueOrNull: the history list must not wait on the favourites request.
    // Not yet loaded reads as "none saved", which shows the save action — and
    // the server refuses a duplicate anyway, so the worst case is one honest
    // error rather than a row that sat disabled for no visible reason.
    final saved =
        ref.watch(favouritesProvider).valueOrNull?.favourites ?? const [];
    // The order stores Arabic names only; the catalogue has the localised
    // ones. Null while it loads, which falls back to the stored name — the
    // list must not wait on the menu either.
    final catalogue = ref.watch(catalogueProvider).valueOrNull;

    // The design's Process / Done tabs: what is still on its way, and what
    // is finished. Ready sits under "in progress" — the drink exists but the
    // order has not stopped moving.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.myOrdersTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.refresh,
              onPressed: () => ref.invalidate(myOrdersProvider),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.liveOrders),
              Tab(text: l10n.pastOrders),
            ],
          ),
        ),
        // skipError: a failed background poll keeps the list it had, with a
        // notice, rather than replacing a Ready order with an error screen.
        // Only a first load with nothing to show falls to the error state.
        body: orders.when(
          skipError: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: l10n.genericError,
            // The server's message, not a generic one: it arrives already
            // localised, and it is the only part that says what failed (§4).
            body: describeError(error, l10n),
            action: OutlinedButton.icon(
              onPressed: () => ref.invalidate(myOrdersProvider),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retry),
            ),
          ),
          data: (all) {
            final stale = orders.hasError
                ? describeError(orders.error!, l10n)
                : null;
            // Status is read by NAME through OrderStatus — never by ordinal,
            // since Ready = 4 sits out of workflow order (rule 5).
            final live = all.where((o) => o.orderStatus.isLive).toList();
            final ready = all
                .where((o) => o.orderStatus == OrderStatus.ready)
                .toList();
            // isSettled, not "everything else": only completed and cancelled
            // orders are finished.
            final past = all.where((o) => o.orderStatus.isSettled).toList();

            // Ready first: a drink waiting is the most urgent thing here.
            final current = [...ready, ...live];

            return TabBarView(
              children: [
                _OrderList(
                  stale: stale,
                  orders: current,
                  emptyIcon: Icons.local_cafe_outlined,
                  emptyTitle: all.isEmpty
                      ? l10n.noOrdersTitle
                      : l10n.noLiveOrders,
                  emptyBody: all.isEmpty
                      ? l10n.noOrdersBody
                      : l10n.noLiveOrdersBody,
                  rowFor: (order) =>
                      _OrderRow(order: order, catalogue: catalogue),
                ),
                _OrderList(
                  stale: stale,
                  orders: past,
                  emptyIcon: Icons.receipt_long_outlined,
                  emptyTitle: all.isEmpty
                      ? l10n.noOrdersTitle
                      : l10n.noPastOrders,
                  emptyBody: all.isEmpty
                      ? l10n.noOrdersBody
                      : l10n.noPastOrdersBody,
                  rowFor: (order) => _OrderRow(
                    order: order,
                    catalogue: catalogue,
                    // Whether this exact order is already saved, so the row
                    // can say so rather than offer to save a second copy.
                    alreadySaved:
                        order.lines.isNotEmpty &&
                        saved.any((f) => f.orders(order.lines)),
                    // Only on a finished order: the user picks WHICH past
                    // order was actually a habit (§7.7). An order with no
                    // lines cannot become a favourite — the server refuses an
                    // empty one — so the action is absent rather than offered
                    // and then rejected.
                    onSaveAsFavourite: order.lines.isEmpty
                        ? null
                        : () => _saveAsFavourite(context, ref, order),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One tab's list, with its own pull-to-refresh and empty state.
class _OrderList extends ConsumerWidget {
  const _OrderList({
    required this.stale,
    required this.orders,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
    required this.rowFor,
  });

  /// Why the last refresh failed, when it did; the list is what was last
  /// loaded.
  final String? stale;
  final List<OrderSummaryDto> orders;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyBody;
  final Widget Function(OrderSummaryDto order) rowFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    Future<void> refresh() async => ref.invalidate(myOrdersProvider);

    final notice = switch (stale) {
      final String reason => InlineBanner(
        tone: BannerTone.warning,
        title: l10n.couldNotRefreshTitle,
        body: reason,
        action: TextButton(
          onPressed: () => ref.invalidate(myOrdersProvider),
          child: Text(l10n.retry),
        ),
      ),
      null => null,
    };

    if (orders.isEmpty) {
      // Stacked over an empty ListView so the pull-to-refresh gesture still
      // works — an empty list you cannot refresh is a dead end. A stale notice
      // shows here too: "none" may only mean the refresh failed.
      return RefreshIndicator(
        onRefresh: refresh,
        child: Stack(
          children: [
            ListView(),
            EmptyState(icon: emptyIcon, title: emptyTitle, body: emptyBody),
            if (notice != null)
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: Dimens.gutter,
                  vertical: Dimens.space4,
                ),
                child: notice,
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Dimens.gutter,
          vertical: Dimens.space4,
        ),
        children: [
          if (notice != null) ...[
            notice,
            const SizedBox(height: Dimens.space3),
          ],
          for (final order in orders) rowFor(order),
        ],
      ),
    );
  }
}

/// Saves a past order to the caller's favourites.
///
/// **No backend work was needed for this**: `OrderSummaryDto.lines` and
/// `SaveFavouriteRequest.lines` are both `OrderLineDto`, so this is a straight
/// repost of the order's own lines.
///
/// Asks what to call it first. The name stays optional — blank means "name it
/// after the drinks", which the server does including the preparation — so the
/// dialog never blocks on typing.
Future<void> _saveAsFavourite(
  BuildContext context,
  WidgetRef ref,
  OrderSummaryDto order,
) async {
  final l10n = AppLocalizations.of(context);
  final locale = ref.read(localeControllerProvider);
  final messenger = ScaffoldMessenger.of(context);

  // Ask what to call it first. The name is optional — blank means "name it
  // after the drinks" — but asking is what lets somebody who keeps several
  // similar orders tell them apart later, which a server-composed name of
  // "قهوة (2 سكر)" repeated three times cannot.
  final choice = await showFavouriteNameDialog(context);
  // Dismissed, or the screen went away while the dialog was open — `ref` and
  // the messenger are both dead past that point.
  if (choice == null || !context.mounted) return;

  try {
    await ref
        .read(favouritesRepositoryProvider)
        .saveFavourite(
          lines: order.lines,
          name: choice.name,
          languageCode: locale.languageCode,
          networkErrorFallback: l10n.networkError,
        );
    ref.invalidate(favouritesProvider);
    messenger.showSnackBar(SnackBar(content: Text(l10n.favouriteSaved)));
  } on ApiException catch (error) {
    // Surfaced as-is: at the cap the server says so, and that message is the
    // only thing that tells the user what to do about it (§4).
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
}

/// One order in the list. Tapping opens the tracking screen.
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.catalogue,
    this.onSaveAsFavourite,
    this.alreadySaved = false,
  });

  final OrderSummaryDto order;

  /// Names the drinks in the reader's language; null while it loads.
  final CatalogueResponse? catalogue;

  /// Offered on finished orders only. Null on a live one — an order still
  /// being made is not yet something the user knows they want again.
  final VoidCallback? onSaveAsFavourite;

  /// Whether this order is already in the user's favourites.
  ///
  /// Turns the action into a filled-star statement rather than a button. The
  /// action is *replaced*, not disabled: a greyed-out control with no
  /// explanation is the dead end this codebase avoids, and "saved" said plainly
  /// is the explanation.
  final bool alreadySaved;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final status = order.orderStatus;

    final (label, tone) = switch (status) {
      OrderStatus.pending => (l10n.statusPending, BrandColors.ink),
      OrderStatus.inProgress => (l10n.statusInProgress, BrandColors.brand),
      OrderStatus.ready => (l10n.statusReady, BrandColors.ok),
      OrderStatus.completed => (l10n.statusCompleted, BrandColors.ink),
      OrderStatus.cancelled => (l10n.statusCancelled, BrandColors.danger),
    };

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: Dimens.space2),
      child: Material(
        color: BrandColors.surface,
        borderRadius: BorderRadius.circular(Dimens.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(Dimens.radius),
          onTap: () => context.push(Routes.orderStatusFor(order.orderId)),
          child: Container(
            constraints: const BoxConstraints(minHeight: Dimens.minTarget),
            padding: const EdgeInsetsDirectional.all(Dimens.space3),
            decoration: BoxDecoration(
              border: Border.all(color: BrandColors.brandLight),
              borderRadius: BorderRadius.circular(Dimens.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            // What was ordered, as the design's rows read:
                            // identical cups once, with ×N. Falls back to the
                            // place for an order that carries no lines.
                            describeOrderDrinks(
                                  order,
                                  catalogue,
                                  l10n,
                                  Localizations.localeOf(context).languageCode,
                                ) ??
                                (order.locationText.trim().isEmpty
                                    ? l10n.noLocationGiven
                                    : Formatters.isolate(order.locationText)),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(color: BrandColors.brandSecondary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Under the drinks rather than beside them: beside,
                          // it split the row with the title and, at a large
                          // text scale, pushed the chevron off the edge. It
                          // always shows — colour is never the only signal
                          // (§2.5).
                          Text(
                            label,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: tone),
                          ),
                          Text(
                            // Converted from UTC — never rendered raw (§4).
                            // The place, when given, is isolated: user-entered
                            // and may run counter to the page direction.
                            [
                              Formatters.dateTime(order.createdAtUtc, locale),
                              if (order.lines.isNotEmpty &&
                                  order.locationText.trim().isNotEmpty)
                                Formatters.isolate(order.locationText),
                            ].join(' · '),
                            style: Theme.of(context).textTheme.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),

                // On its own line rather than in the row above: at 320dp the
                // row already carries a location, a date, a status word and a
                // chevron, and a fourth control squeezed in beside them is how
                // the status label got pushed off the edge before. A full-width
                // button below also states what it does in words, which an
                // icon in a crowded row could not.
                if (alreadySaved) ...[
                  const SizedBox(height: Dimens.space2),
                  // A filled star and a statement, not a button: there is
                  // nothing left to do here, and offering the action again
                  // would either save a duplicate or produce a rejection the
                  // user could not have predicted.
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: Dimens.space2,
                        top: Dimens.space1,
                        bottom: Dimens.space1,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star,
                            size: 16,
                            color: BrandColors.brand,
                          ),
                          const SizedBox(width: Dimens.space2),
                          Flexible(
                            child: Text(
                              l10n.favouriteAlreadySaved,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(color: BrandColors.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else if (onSaveAsFavourite case final VoidCallback save) ...[
                  const SizedBox(height: Dimens.space2),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: save,
                      icon: const Icon(Icons.star_outline, size: 16),
                      label: Text(l10n.saveAsFavourite),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
