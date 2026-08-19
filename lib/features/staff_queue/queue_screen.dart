import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/api/api_config.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/staff_models.dart';
import '../../data/repositories/queue_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/widgets/banners.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import 'widgets/queue_card.dart';

/// The staff home screen.
///
/// Two lists, because `GET /staff/queue` returns **`Pending` + `InProgress`
/// only** — an order marked `Ready` leaves that list, so handovers need a
/// separate `?status=Ready` fetch (§8.1).
///
/// There is deliberately **no declarations tab**: those endpoints are
/// admin-only and a Staff token gets `403` on all three (§8.2).
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  Timer? _pollTimer;

  List<StaffOrderDto> _queue = [];
  List<StaffOrderDto> _handovers = [];
  bool _loading = true;
  String? _errorMessage;

  /// Warnings from the most recent serve, shown on the card afterwards.
  final Map<int, List<StockWarningDto>> _recentWarnings = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _tabController.dispose();
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
        _pollTimer?.cancel();
    }
  }

  /// ~10s foregrounded. Staff keep this screen open, and a stale queue is worse
  /// than a slightly chatty one (§8.1).
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      ApiConfig.queuePollInterval,
      (_) => unawaited(_refresh()),
    );
  }

  Future<void> _refresh() async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);
    final repository = ref.read(queueRepositoryProvider);

    try {
      final results = await Future.wait([
        repository.fetchQueue(
          languageCode: locale.languageCode,
          networkErrorFallback: l10n.networkError,
        ),
        repository.fetchReadyForHandover(
          languageCode: locale.languageCode,
          networkErrorFallback: l10n.networkError,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _queue = results[0];
        _handovers = results[1];
        _loading = false;
        _errorMessage = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    }
  }

  /// Marks an order ready — **the only path that deducts stock**.
  ///
  /// A `200` carrying warnings is still success: the drink was made. The
  /// warnings are surfaced on the card and never treated as a failure.
  Future<void> _markReady(
    StaffOrderDto order, {
    required bool deliverNow,
  }) async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);

    try {
      final result = await ref
          .read(queueRepositoryProvider)
          .markReady(
            orderId: order.orderId,
            deliverNow: deliverNow,
            languageCode: locale.languageCode,
            networkErrorFallback: l10n.networkError,
          );

      if (!mounted) return;

      if (result.hasWarnings) {
        setState(() => _recentWarnings[order.orderId] = result.warnings);
      }

      await _refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.orderServed)));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _complete(StaffOrderDto order) async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);

    try {
      await ref
          .read(queueRepositoryProvider)
          .complete(
            orderId: order.orderId,
            languageCode: locale.languageCode,
            networkErrorFallback: l10n.networkError,
          );
      await _refresh();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.queueTitle),
        actions: [
          Center(
            child: Text(
              l10n.orderCount(_queue.length),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: BrandColors.surface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settings,
            onPressed: () => context.push(Routes.settings),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // accentBright marks position on the navy bar — non-text UI only,
          // never carrying a label (§2.2).
          indicatorColor: BrandColors.accentBright,
          labelColor: BrandColors.surface,
          unselectedLabelColor: BrandColors.accentBright,
          tabs: [
            Tab(text: l10n.queueTab),
            Tab(text: l10n.handoverTab),
          ],
        ),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _queue.isEmpty && _handovers.isEmpty
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
          : TabBarView(
              controller: _tabController,
              children: [
                _QueueList(
                  orders: _queue,
                  warnings: _recentWarnings,
                  emptyTitle: l10n.emptyQueueTitle,
                  emptyBody: l10n.emptyQueueBody,
                  onRefresh: _refresh,
                  onMarkReady: _markReady,
                  onComplete: null,
                ),
                _QueueList(
                  orders: _handovers,
                  warnings: _recentWarnings,
                  emptyTitle: l10n.noHandoversTitle,
                  emptyBody: l10n.noHandoversBody,
                  onRefresh: _refresh,
                  onMarkReady: null,
                  onComplete: _complete,
                ),
              ],
            ),
    );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList({
    required this.orders,
    required this.warnings,
    required this.emptyTitle,
    required this.emptyBody,
    required this.onRefresh,
    required this.onMarkReady,
    required this.onComplete,
  });

  final List<StaffOrderDto> orders;
  final Map<int, List<StockWarningDto>> warnings;
  final String emptyTitle;
  final String emptyBody;
  final Future<void> Function() onRefresh;
  final Future<void> Function(StaffOrderDto, {required bool deliverNow})?
  onMarkReady;
  final Future<void> Function(StaffOrderDto)? onComplete;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: Stack(
          children: [
            ListView(),
            EmptyState(
              icon: Icons.inbox_outlined,
              title: emptyTitle,
              body: emptyBody,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.all(Dimens.space4),
        itemCount: orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: Dimens.space3),
        itemBuilder: (context, index) {
          final order = orders[index];
          return QueueCard(
            order: order,
            warnings: warnings[order.orderId],
            onMarkReady: onMarkReady,
            onComplete: onComplete,
          );
        },
      ),
    );
  }
}
