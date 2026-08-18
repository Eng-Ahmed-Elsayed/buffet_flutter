import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/api/api_config.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/catalogue_models.dart';
import '../../data/models/order_models.dart';
import '../../data/repositories/order_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/source_chip.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';

/// Live status for one order.
///
/// Polls every ~15s **while foregrounded**, stops on background, refreshes once
/// on resume, and stops entirely once the order is no longer live. There are no
/// push notifications or websockets in this system (§7.3).
class OrderStatusScreen extends ConsumerStatefulWidget {
  const OrderStatusScreen({required this.orderId, super.key});

  final int orderId;

  @override
  ConsumerState<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends ConsumerState<OrderStatusScreen>
    with WidgetsBindingObserver {
  Timer? _pollTimer;
  OrderSummaryDto? _order;
  String? _errorMessage;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _startPolling();
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
      case AppLifecycleState.resumed:
        unawaited(_refresh());
        _startPolling();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Nothing to poll for while the user cannot see it.
        _pollTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      ApiConfig.orderPollInterval,
      (_) => unawaited(_refresh()),
    );
  }

  Future<void> _refresh() async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);

    try {
      final order = await ref
          .read(orderRepositoryProvider)
          .fetchOrder(
            orderId: widget.orderId,
            languageCode: locale.languageCode,
            networkErrorFallback: l10n.networkError,
          );

      if (!mounted) return;
      setState(() {
        _order = order;
        _errorMessage = null;
      });

      // A completed or cancelled order will never change again.
      if (!order.orderStatus.isLive) _pollTimer?.cancel();
    } on ApiException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    }
  }

  Future<void> _cancel() async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);

    setState(() => _cancelling = true);
    try {
      await ref
          .read(orderRepositoryProvider)
          .cancelOrder(
            orderId: widget.orderId,
            languageCode: locale.languageCode,
            networkErrorFallback: l10n.networkError,
          );
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final order = _order;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.myOrderTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(Routes.catalogue),
        ),
      ),
      body: order == null
          ? _errorMessage != null
                ? EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: l10n.genericError,
                    body: _errorMessage!,
                    action: OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  )
                : const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsetsDirectional.all(Dimens.space4),
                children: [
                  _StatusHeader(status: order.orderStatus),
                  const SizedBox(height: Dimens.space5),
                  _StatusTrack(status: order.orderStatus),
                  const SizedBox(height: Dimens.space5),
                  for (final line in order.lines) ...[
                    _OrderLineCard(line: line, order: order),
                    const SizedBox(height: Dimens.space3),
                  ],

                  // Cancellation is pending-only and ownership-checked. The
                  // action is HIDDEN once the status leaves Pending, rather
                  // than shown as a button that will 400 (§7.3).
                  if (order.orderStatus.isCancellable) ...[
                    const SizedBox(height: Dimens.space3),
                    OutlinedButton(
                      onPressed: _cancelling ? null : _cancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BrandColors.danger,
                        side: const BorderSide(color: BrandColors.danger),
                      ),
                      child: Text(l10n.cancelOrder),
                    ),
                  ],

                  if (order.orderStatus == OrderStatus.completed) ...[
                    const SizedBox(height: Dimens.space3),
                    FilledButton.icon(
                      onPressed: () => context.go(Routes.catalogue),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.orderAgain),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

/// The headline state.
///
/// `Ready` gets the loudest treatment in the app — it is the "come and collect
/// it" moment. `Completed` is deliberately quieter (§4.3).
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isReady = status == OrderStatus.ready;

    final (label, body, icon, background, foreground) = switch (status) {
      OrderStatus.pending => (
        l10n.statusPending,
        l10n.pendingBody,
        Icons.schedule,
        BrandColors.surface,
        BrandColors.ink,
      ),
      OrderStatus.inProgress => (
        l10n.statusInProgress,
        l10n.inProgressBody,
        Icons.coffee_maker_outlined,
        BrandColors.surface,
        BrandColors.brand,
      ),
      OrderStatus.ready => (
        l10n.statusReady,
        l10n.readyBody,
        Icons.check_rounded,
        BrandColors.ok,
        BrandColors.surface,
      ),
      OrderStatus.completed => (
        l10n.statusCompleted,
        '',
        Icons.check_circle_outline,
        BrandColors.surface,
        BrandColors.ink,
      ),
      OrderStatus.cancelled => (
        l10n.statusCancelled,
        '',
        Icons.cancel_outlined,
        BrandColors.surface,
        BrandColors.danger,
      ),
    };

    return Semantics(
      liveRegion: true,
      // Status is never colour alone — the word is always present (§2.5).
      label: label,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Dimens.space4,
          vertical: Dimens.space6,
        ),
        decoration: BoxDecoration(
          color: background,
          border: isReady ? null : Border.all(color: BrandColors.brandLight),
          borderRadius: BorderRadius.circular(Dimens.radiusLg),
        ),
        child: Column(
          children: [
            Icon(icon, size: isReady ? 40 : 30, color: foreground),
            const SizedBox(height: Dimens.space3),
            Text(
              label,
              style:
                  (isReady
                          ? Theme.of(context).textTheme.headlineMedium
                          : Theme.of(context).textTheme.headlineSmall)
                      ?.copyWith(color: foreground),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: Dimens.space1),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isReady ? BrandColors.surface : BrandColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The four-step progress track. Cancelled orders have no track — they left
/// the workflow.
class _StatusTrack extends StatelessWidget {
  const _StatusTrack({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    if (status == OrderStatus.cancelled) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    // Compared by name via the enum — the server's ordinals are not in
    // workflow order (Ready = 4).
    const order = [
      OrderStatus.pending,
      OrderStatus.inProgress,
      OrderStatus.ready,
      OrderStatus.completed,
    ];
    final currentIndex = order.indexOf(status);

    final labels = [
      l10n.statusPending,
      l10n.statusInProgress,
      l10n.statusReady,
      l10n.statusCompleted,
    ];

    return Row(
      children: [
        for (var i = 0; i < order.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsetsDirectional.only(bottom: Dimens.space5),
                color: i <= currentIndex
                    ? (currentIndex >= 2 ? BrandColors.ok : BrandColors.brand)
                    : BrandColors.brandLight,
              ),
            ),
          SizedBox(
            width: 72,
            child: Column(
              children: [
                Container(
                  width: i == currentIndex ? 18 : 14,
                  height: i == currentIndex ? 18 : 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i > currentIndex
                        ? BrandColors.brandLight
                        : (currentIndex >= 2 && i >= 2
                              ? BrandColors.ok
                              : BrandColors.brand),
                  ),
                ),
                const SizedBox(height: Dimens.space1),
                Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: i == currentIndex
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: i == currentIndex
                        ? (currentIndex >= 2
                              ? BrandColors.ok
                              : BrandColors.brand)
                        : BrandColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderLineCard extends StatelessWidget {
  const _OrderLineCard({required this.line, required this.order});

  final OrderLineDto line;
  final OrderSummaryDto order;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    return Container(
      padding: const EdgeInsetsDirectional.all(Dimens.space4),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border.all(color: BrandColors.brandLight),
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.drinkNameAr, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: Dimens.space2),
          Wrap(
            spacing: Dimens.space2,
            runSpacing: Dimens.space2,
            children: [
              DetailChip(label: l10n.spoons(line.sugarSpoons)),
              if (line.drinkFromOwn)
                SourceChip(label: l10n.drink, ownerName: _ownLabel(context)),
            ],
          ),
          const SizedBox(height: Dimens.space3),
          const Divider(),
          const SizedBox(height: Dimens.space2),
          Row(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 16,
                color: BrandColors.muted,
              ),
              const SizedBox(width: Dimens.space2),
              Expanded(
                child: Text(
                  order.locationText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (order.readyAtUtc != null) ...[
            const SizedBox(height: Dimens.space1),
            Row(
              children: [
                const Icon(Icons.schedule, size: 16, color: BrandColors.muted),
                const SizedBox(width: Dimens.space2),
                Text(
                  // UTC in, local out — never render a raw ...Utc value.
                  Formatters.timeOfDay(order.readyAtUtc!, locale),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// On the employee's own screen "my jar" needs no name — the owner is the
  /// person reading it.
  String _ownLabel(BuildContext context) =>
      AppLocalizations.of(context).fromMyMaterials;
}
