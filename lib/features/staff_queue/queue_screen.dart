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
import '../../shared/widgets/exit_confirmation.dart';
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

  /// Orders whose serve is inside its undo window: hidden from the lists so
  /// staff cannot tap the same cup twice, but not yet sent.
  final Map<int, StaffOrderDto> _pendingActions = {};
  final Map<int, Timer> _pendingTimers = {};
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
    // Pending actions are abandoned rather than fired: leaving the screen is
    // not a confirmation, and a timer outliving dispose would call setState
    // on a dead State.
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
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
  /// Marks ready **after a short undo window**, not immediately.
  ///
  /// §8.1 wants one tap with an undo, not a confirm dialog — staff hands are
  /// busy. The undo must happen *before* the call: `/ready` is the only path
  /// that writes ledger rows and the API has no un-ready endpoint, so there is
  /// no way back once it fires. Cancelling the customer's order is a different
  /// act, not a reversal.
  Future<void> _markReadyAfterUndoWindow(
    StaffOrderDto order, {
    required bool deliverNow,
  }) async {
    // A second tap while one is already pending would serve it twice.
    if (_pendingActions.containsKey(order.orderId)) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _pendingActions[order.orderId] = order);

    final timer = Timer(ApiConfig.undoWindow, () {
      _pendingTimers.remove(order.orderId);
      if (!mounted) return;
      setState(() => _pendingActions.remove(order.orderId));
      unawaited(_markReady(order, deliverNow: deliverNow));
    });
    _pendingTimers[order.orderId] = timer;

    messenger.showSnackBar(
      SnackBar(
        duration: ApiConfig.undoWindow,
        content: Text(l10n.undoWindowMessage(order.orderId)),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () {
            timer.cancel();
            _pendingTimers.remove(order.orderId);
            // Dismissing the snackbar is NOT an undo — only this is. The card
            // comes back and nothing was sent.
            if (mounted) {
              setState(() => _pendingActions.remove(order.orderId));
            }
          },
        ),
      ),
    );
  }

  /// Drops orders whose action is still inside its undo window.
  List<StaffOrderDto> _visible(List<StaffOrderDto> orders) =>
      orders.where((o) => !_pendingActions.containsKey(o.orderId)).toList();

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

  /// Cancels an order, asking for a reason first.
  ///
  /// **The one staff action that gets a dialog** (§8.1). Everything else is one
  /// tap with an undo window; this one takes a reason and cannot be walked
  /// back by simply not sending it, so a deliberate confirmation is right
  /// rather than an obstacle.
  ///
  /// Cancelling a `Ready` order reverses the consumption and re-books it as
  /// waste server-side — the balance is unchanged, but nobody is credited with
  /// a drink they never received.
  Future<void> _cancel(StaffOrderDto order) async {
    final l10n = AppLocalizations.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(orderId: order.orderId),
    );

    // Dismissing the dialog cancels the cancellation, not the order.
    if (reason == null || !mounted) return;

    final locale = ref.read(localeControllerProvider);
    try {
      await ref
          .read(queueRepositoryProvider)
          .cancel(
            orderId: order.orderId,
            reason: reason.trim().isEmpty ? null : reason.trim(),
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

    return ExitConfirmation(
      // A landing screen: nothing sits beneath it in the stack, so back
      // would otherwise close the app outright.
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.queueTitle),
          actions: [
            Center(
              child: Text(
                // Counts what is actually on screen. Using the unfiltered
                // list made the header claim "one order" while the list showed
                // its empty state, for the length of an undo window.
                l10n.orderCount(_visible(_queue).length),
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
                    // Orders inside their undo window are hidden so staff do
                    // not serve the same cup twice while it is pending.
                    orders: _visible(_queue),
                    warnings: _recentWarnings,
                    emptyTitle: l10n.emptyQueueTitle,
                    emptyBody: l10n.emptyQueueBody,
                    onRefresh: _refresh,
                    onMarkReady: _markReadyAfterUndoWindow,
                    onComplete: null,
                    onCancel: _cancel,
                  ),
                  _QueueList(
                    orders: _visible(_handovers),
                    warnings: _recentWarnings,
                    emptyTitle: l10n.noHandoversTitle,
                    emptyBody: l10n.noHandoversBody,
                    onRefresh: _refresh,
                    onMarkReady: null,
                    onComplete: _complete,
                    // Not offered on the handover list: the drink is already
                    // made and stock already deducted, so cancelling there is
                    // the wrong remedy.
                    onCancel: null,
                  ),
                ],
              ),
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
    required this.onCancel,
  });

  final List<StaffOrderDto> orders;
  final Map<int, List<StockWarningDto>> warnings;
  final String emptyTitle;
  final String emptyBody;
  final Future<void> Function() onRefresh;
  final Future<void> Function(StaffOrderDto, {required bool deliverNow})?
  onMarkReady;
  final Future<void> Function(StaffOrderDto)? onComplete;
  final Future<void> Function(StaffOrderDto)? onCancel;

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
            onCancel: onCancel,
          );
        },
      ),
    );
  }
}

/// Asks for a cancellation reason.
///
/// Returns the reason on confirm and null on dismiss — dismissing cancels the
/// cancellation, not the order. The reason is optional on the wire, so an
/// empty field is allowed rather than blocked: forcing text would invite "x".
class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.orderId});

  final int orderId;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Text(l10n.cancelWithReason),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(labelText: l10n.cancelReason),
        autofocus: true,
        maxLines: 2,
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          style: TextButton.styleFrom(foregroundColor: BrandColors.danger),
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}
