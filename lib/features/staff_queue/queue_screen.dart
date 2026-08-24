import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import '../order/self_order_outcome.dart';
import 'pending_action.dart';
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

  /// Orders whose action is inside its undo window — tapped, not yet sent.
  ///
  /// These stay *in* the list: the card carries its own countdown and undo
  /// button, and its actions are swapped out so the same cup cannot be tapped
  /// twice. Hiding the card and putting the undo in a SnackBar is what made the
  /// undo unusable under a rush.
  final Map<int, PendingAction> _pendingActions = {};
  final Map<int, Timer> _pendingTimers = {};

  /// Handovers already sent and awaiting their response, so a second tap during
  /// the round trip cannot post twice.
  final Set<int> _completing = {};
  bool _loading = true;
  String? _errorMessage;

  /// Warnings from the most recent serve, shown on the card afterwards.
  final Map<int, List<StockWarningDto>> _recentWarnings = {};

  /// The result of a self-order just placed, shown as a banner above the tabs.
  SelfOrderOutcome? _selfOrderOutcome;

  /// Held so [_flushPending] can send from `dispose`, where `ref` has already
  /// been torn down and reading it throws.
  QueueRepository? _repositoryForFlush;
  String _languageForFlush = 'ar';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // The header count follows the visible tab, so it has to rebuild when the
    // tab changes — otherwise it reports the queue while the handover list is
    // on screen.
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, not during initState: _refresh reads
    // AppLocalizations for its network-error fallback, and an inherited widget
    // cannot legally be looked up before initState has returned.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _flushPending();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_refresh());
        _startPolling();

      // Going to the background is the last moment we are guaranteed to run: a
      // Timer is not promised to fire while backgrounded, and an app killed in
      // Doze loses the send outright. So the window is cut short and the action
      // goes now.
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _pollTimer?.cancel();
        _flushPending();

      // Not a backgrounding. `inactive` fires for a notification-shade pull or
      // an incoming call, with the card still on screen and seconds left on a
      // countdown the user can watch — sending there would contradict it.
      case AppLifecycleState.inactive:
        _pollTimer?.cancel();
    }
  }

  /// Sends every action still inside its undo window, right now.
  ///
  /// The drink was already made when the button was pressed: this tap records a
  /// physical event, and dropping it leaves the ledger disagreeing with the
  /// shelf. Losing a tap is not the safe outcome, it is the expensive one.
  ///
  /// Deliberately does not go through [_markReady] or [_complete] — those touch
  /// `setState` and `context`, and this runs from `dispose`. Errors are
  /// swallowed because there is no UI left to report to, and the server-side
  /// outcome is recoverable: a failed `/ready` leaves the order Pending and it
  /// comes back on the next fetch.
  void _flushPending() {
    if (_pendingActions.isEmpty) return;

    // Captured rather than read: this runs from `dispose`, where `ref` has
    // already been torn down.
    final repository = _repositoryForFlush;
    if (repository == null) return;
    final language = _languageForFlush;

    for (final entry in _pendingActions.entries.toList()) {
      _pendingTimers.remove(entry.key)?.cancel();
      final action = entry.value;

      final send = switch (action.kind) {
        PendingActionKind.ready => repository.markReady(
          orderId: entry.key,
          deliverNow: action.deliverNow,
          languageCode: language,
          networkErrorFallback: '',
        ),
        PendingActionKind.complete => repository.complete(
          orderId: entry.key,
          languageCode: language,
          networkErrorFallback: '',
        ),
      };

      // An unhandled Future error escaping dispose would take down the zone.
      unawaited(send.then((_) {}, onError: (_) {}));
    }

    _pendingActions.clear();
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
    _repositoryForFlush = repository;
    _languageForFlush = locale.languageCode;

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

    // A screen reader stretches the window rather than losing the control
    // mid-sentence: a timed affordance carrying the only way out of an action
    // is a WCAG 2.2 SC 2.2.1 problem, and Flutter's own SnackBar stops timing
    // out under TalkBack for the same reason.
    final window = MediaQuery.of(context).accessibleNavigation
        ? ApiConfig.undoWindowAccessible
        : ApiConfig.undoWindow;

    setState(() {
      _pendingActions[order.orderId] = PendingAction(
        kind: PendingActionKind.ready,
        deliverNow: deliverNow,
        deadline: DateTime.now().add(window),
      );
    });

    _pendingTimers[order.orderId] = Timer(window, () {
      _pendingTimers.remove(order.orderId);
      if (!mounted) return;
      setState(() => _pendingActions.remove(order.orderId));
      unawaited(_markReady(order, deliverNow: deliverNow));
    });
  }

  /// Cancels a pending action before it is sent. Nothing reaches the API.
  void _undo(StaffOrderDto order) {
    if (!_pendingActions.containsKey(order.orderId)) return;

    _pendingTimers.remove(order.orderId)?.cancel();
    setState(() => _pendingActions.remove(order.orderId));

    _announce(AppLocalizations.of(context).undoneAnnouncement);
  }

  /// Speaks a change the screen reader would otherwise miss.
  ///
  /// The visible confirmation for these is the list changing, which a screen
  /// reader does not narrate on its own.
  void _announce(String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

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
      // No toast. The card leaving the list is the confirmation, and the user
      // has just watched the countdown commit — a second, later signal for the
      // same event is exactly the noise that made the old undo unreadable.
      // Announced for screen readers, who cannot see the list change.
      _announce(l10n.orderServed);
    } on ApiException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    }
  }

  /// Errors are rare and must be seen, so a queued backlog of three identical
  /// network failures is cleared before showing the newest.
  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      _showError(error.message);
    }
  }

  /// Hands an order over. **Immediate, with no undo window and no dialog.**
  ///
  /// Unlike `/ready`, this writes no ledger rows: a mistaken handover is a
  /// paperwork discrepancy the next person resolves by walking to the counter,
  /// where a mistaken serve is a stock discrepancy an admin reconciles weeks
  /// later from a report. Making every legitimate handover five seconds slower
  /// to guard the cheaper mistake is a bad trade.
  Future<void> _complete(StaffOrderDto order) async {
    // Without this a second tap during the round trip posts again, and the
    // server's compare-and-swap rejects it — so the user got an error for
    // having tapped twice.
    if (!_completing.add(order.orderId)) return;

    final l10n = AppLocalizations.of(context);
    final locale = ref.read(localeControllerProvider);

    // Removed before the await so the row cannot be tapped again, and put back
    // if the call fails — the order really is still awaiting handover.
    setState(() => _handovers.removeWhere((o) => o.orderId == order.orderId));

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
      setState(() => _handovers = [order, ..._handovers]);
      _showError(error.message);
    } finally {
      _completing.remove(order.orderId);
    }
  }

  /// Opens the composer so a staff member can make their own drink.
  ///
  /// `push`, not `go`: the queue is their home and stays beneath, so the
  /// composer's back arrow returns them to work rather than to the catalogue.
  Future<void> _orderForMyself() async {
    final outcome = await context.push<SelfOrderOutcome>(Routes.catalogue);
    if (!mounted || outcome == null) return;

    setState(() => _selfOrderOutcome = outcome);
    await _refresh();
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
                // Counts what is actually on screen — the VISIBLE tab's list.
                // Counting the queue unconditionally made the header read "no
                // orders" above a handover list holding three. Pending cards
                // stay in the list now, so they stay in the count too: they are
                // on screen, and the drink is still the staff member's to make
                // until the window closes.
                l10n.orderCount(
                  (_tabController.index == 0 ? _queue : _handovers).length,
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: BrandColors.surface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            // Staff drink too, and had no way into the composer at all — the
            // queue is their home screen and nothing linked out of it.
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: l10n.orderForMyself,
              onPressed: _orderForMyself,
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

        body: Column(
          children: [
            if (_selfOrderOutcome case final outcome?)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  Dimens.space4,
                  Dimens.space3,
                  Dimens.space4,
                  0,
                ),
                child: InlineBanner(
                  // Neither is dismissed on a timer. A shortage names stock
                  // that has drifted and somebody should read it; the success
                  // case is the only confirmation a self-order ever gets,
                  // since there is no status screen to send them to.
                  tone: outcome.hasShortages
                      ? BannerTone.warning
                      : BannerTone.info,
                  title: outcome.hasShortages
                      ? l10n.preparedWithShortages(outcome.shortageNames!)
                      : l10n.selfOrderCompleted(outcome.orderId),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.dismiss,
                    onPressed: () => setState(() => _selfOrderOutcome = null),
                  ),
                ),
              ),
            Expanded(child: _body(l10n)),
          ],
        ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    return _loading
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
                pending: _pendingActions,
                onUndo: _undo,
                warnings: _recentWarnings,
                emptyTitle: l10n.emptyQueueTitle,
                emptyBody: l10n.emptyQueueBody,
                onRefresh: _refresh,
                onMarkReady: _markReadyAfterUndoWindow,
                onComplete: null,
                onCancel: _cancel,
              ),
              _QueueList(
                orders: _handovers,
                pending: _pendingActions,
                onUndo: _undo,
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
          );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList({
    required this.orders,
    required this.pending,
    required this.onUndo,
    required this.warnings,
    required this.emptyTitle,
    required this.emptyBody,
    required this.onRefresh,
    required this.onMarkReady,
    required this.onComplete,
    required this.onCancel,
  });

  final List<StaffOrderDto> orders;
  final Map<int, PendingAction> pending;
  final void Function(StaffOrderDto) onUndo;
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
            key: ValueKey(order.orderId),
            order: order,
            warnings: warnings[order.orderId],
            pending: pending[order.orderId],
            onUndo: () => onUndo(order),
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
