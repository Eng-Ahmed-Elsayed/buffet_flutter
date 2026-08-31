import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/order_models.dart';
import '../../data/repositories/order_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/section_header.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// The caller's own orders, newest first.
final myOrdersProvider = FutureProvider.autoDispose<List<OrderSummaryDto>>((
  ref,
) async {
  final locale = ref.watch(localeControllerProvider);
  return ref
      .watch(orderRepositoryProvider)
      .fetchMyOrders(
        languageCode: locale.languageCode,
        networkErrorFallback: 'network',
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myOrdersTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: () => ref.invalidate(myOrdersProvider),
          ),
        ],
      ),
      body: orders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: l10n.genericError,
          // The server's message, not a generic one: it arrives already
          // localised, and it is the only part that says what actually
          // failed (§4).
          body: error is ApiException ? error.message : l10n.networkError,
          action: OutlinedButton.icon(
            onPressed: () => ref.invalidate(myOrdersProvider),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ),
        data: (all) {
          if (all.isEmpty) {
            // Stacked over an empty ListView so the pull-to-refresh gesture
            // still works — the same trick the queue and notification lists
            // use. An empty list you cannot refresh is a dead end.
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(myOrdersProvider),
              child: Stack(
                children: [
                  ListView(),
                  EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: l10n.noOrdersTitle,
                    body: l10n.noOrdersBody,
                  ),
                ],
              ),
            );
          }

          // Status is read by NAME through OrderStatus — never by ordinal,
          // since Ready = 4 sits out of workflow order (rule 5).
          final live = all.where((o) => o.orderStatus.isLive).toList();
          final ready = all
              .where((o) => o.orderStatus == OrderStatus.ready)
              .toList();
          // isSettled, not "everything else": only completed and cancelled
          // orders are finished. Ready belongs above with the live ones — the
          // drink exists but the order has not stopped moving.
          final past = all.where((o) => o.orderStatus.isSettled).toList();

          // Ready first: a drink waiting on the counter is the most urgent
          // thing on this screen.
          final current = [...ready, ...live];

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myOrdersProvider),
            child: ListView(
              padding: const EdgeInsetsDirectional.all(Dimens.space4),
              children: [
                if (current.isNotEmpty) ...[
                  SectionHeader(label: l10n.liveOrders),
                  const SizedBox(height: Dimens.space2),
                  for (final order in current) _OrderRow(order: order),
                  const SizedBox(height: Dimens.space5),
                ],
                if (past.isNotEmpty) ...[
                  SectionHeader(label: l10n.pastOrders),
                  const SizedBox(height: Dimens.space2),
                  for (final order in past) _OrderRow(order: order),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One order in the list. Tapping opens the tracking screen.
class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final OrderSummaryDto order;

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
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // locationText is optional — an order stands without
                        // one, so an empty string is a normal state and must
                        // read as "none given" rather than as a blank row.
                        order.locationText.trim().isEmpty
                            ? l10n.noLocationGiven
                            // Isolated: user- or admin-entered, and may run
                            // counter to the page direction (§2.4).
                            : Formatters.isolate(order.locationText),
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        // Converted from UTC — never rendered raw (§4).
                        Formatters.dateTime(order.createdAtUtc, locale),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Dimens.space2),
                // Constrained rather than free: at a large text scale the
                // status word alone was wider than the row and pushed the
                // chevron off the edge. It still always shows — colour is
                // never the only signal (§2.5) — it just wraps instead.
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: tone),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
