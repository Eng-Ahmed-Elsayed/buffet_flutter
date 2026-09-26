import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/landing_prompts.dart';
import '../../app/locale_controller.dart';
import '../../app/routes.dart';
import '../../data/api/api_config.dart';
import '../../data/api/api_exception.dart';
import '../../data/models/staff_models.dart';
import '../../data/repositories/queue_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/formatters.dart';
import '../../shared/tab_labels.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/brand_lockup.dart';
import '../../shared/widgets/exit_confirmation.dart';
import '../../shared/widgets/notification_bell.dart';
import '../../theme/brand_colors.dart';
import '../../theme/dimens.dart';
import '../auth/auth_controller.dart';
import '../notifications/notifications_screen.dart';
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

  /// Orders whose undo window has committed and whose `/ready` is on its way.
  /// Kept out of every refresh until the answer lands: a poll answered before
  /// the server handled the serve still lists the order as Pending, and
  /// putting its card back with live buttons is the double serve the removal
  /// exists to prevent — the normal case when a rush serves cards back to back.
  final Set<int> _serving = {};
  bool _loading = true;
  String? _errorMessage;

  /// Warnings from the most recent serve, shown on the card afterwards.
  final Map<int, List<StockWarningDto>> _recentWarnings = {};

  /// Shortages from orders served AND handed over at once. Those orders leave
  /// both lists, so a warning kept on their card was never seen — on the most
  /// used button (rule 2: surface it after serving). Shown above the tabs
  /// until dismissed, newest first.
  final List<({int orderId, String name, List<StockWarningDto> warnings})>
  _servedShortages = [];

  /// The result of a self-order just placed, shown as a banner above the tabs.
  SelfOrderOutcome? _selfOrderOutcome;

  /// Held so [_flushPending] can send from `dispose`, where `ref` has already
  /// been torn down and reading it throws.
  QueueRepository? _repositoryForFlush;
  String _languageForFlush = 'ar';

  /// Where [_flushPending] is registered to run before sign-out.
  AuthController? _authForFlush;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // The header count follows the visible tab, so it has to rebuild when the
    // tab changes — otherwise it reports the queue while the handover list is
    // on screen.
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addObserver(this);
    final auth = ref.read(authControllerProvider.notifier);
    _authForFlush = auth;
    auth.beforeSignOut.add(_flushPending);
    // After the first frame, not during initState: _refresh reads
    // AppLocalizations for its network-error fallback, and an inherited widget
    // cannot legally be looked up before initState has returned.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refresh());
      // Staff never got this. The prompt used to live on the composer, which
      // is the EMPLOYEE landing screen — staff only ever reach it by pushing
      // it from here, so a staff member who never ordered their own drink had
      // no notification channels and was never asked for permission at all.
      unawaited(prepareLandingPrompts(context, ref));
    });
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _authForFlush?.beforeSignOut.remove(_flushPending);
    unawaited(_flushPending());
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
        unawaited(_flushPending());

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
  ///
  /// Also run by sign-out, before the token goes (see
  /// [AuthController.beforeSignOut]): from `dispose` alone it ran after, so
  /// every send arrived unauthenticated and was lost.
  Future<void> _flushPending() {
    if (_pendingActions.isEmpty) return Future.value();

    // Captured rather than read: this runs from `dispose`, where `ref` has
    // already been torn down.
    final repository = _repositoryForFlush;
    if (repository == null) return Future.value();
    final language = _languageForFlush;

    final sends = <Future<void>>[];
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
      sends.add(send.then((_) {}, onError: (_) {}));
    }

    _pendingActions.clear();
    return Future.wait(sends);
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

  /// When the lists on screen were last loaded, for the stale notice.
  DateTime? _loadedAt;

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
        _queue = [
          for (final o in results[0])
            if (!_serving.contains(o.orderId)) o,
        ];
        _handovers = results[1];
        _loading = false;
        _errorMessage = null;
        _loadedAt = DateTime.now();
      });
      // The bell's badge reads this list, and nothing else reloads it.
      ref.invalidate(notificationsProvider);
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
      unawaited(_commit(order, deliverNow: deliverNow));
    });
  }

  /// Sends a serve whose window has closed.
  Future<void> _commit(StaffOrderDto order, {required bool deliverNow}) {
    // The card goes as the countdown commits, as a handover's does. Left in
    // place until the server answered, it showed its Ready buttons again for
    // the whole round trip — read as "undone", and served twice.
    setState(() {
      _pendingActions.remove(order.orderId);
      _serving.add(order.orderId);
      _queue = _queue.where((o) => o.orderId != order.orderId).toList();
    });
    return _markReady(order, deliverNow: deliverNow);
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

      final whom = order.onBehalfOfName ?? order.requesterDisplayName;
      if (result.hasWarnings) {
        setState(() {
          if (deliverNow) {
            _servedShortages.insert(0, (
              orderId: order.orderId,
              // Who the drink was for: the guest, when there is one.
              name: whom,
              warnings: result.warnings,
            ));
          } else {
            // Plain Ready: the card moves to the handover list and carries
            // its warnings there.
            _recentWarnings[order.orderId] = result.warnings;
          }
        });
      }

      // The answer has landed: from here the server's lists are right about
      // this order, so refreshes may list it again (as Ready, on handover).
      _serving.remove(order.orderId);
      await _refresh();

      if (!mounted) return;
      // No toast. The card leaving the list is the confirmation, and the user
      // has just watched the countdown commit — a second, later signal for the
      // same event is exactly the noise that made the old undo unreadable.
      // Announced for screen readers, who cannot see the list change — and a
      // shortage said too, since its notice appears without a word.
      _announce(
        !deliverNow
            ? l10n.orderServed
            : result.hasWarnings
            ? l10n.servedWithShortage(whom)
            : l10n.orderServedAndHandedOver,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      _serving.remove(order.orderId);
      // Put back: the order may well still be waiting to be served. Then
      // reconciled at once, since some failures mean it no longer is (served
      // on another device, cancelled during the window).
      setState(() {
        if (!_queue.any((o) => o.orderId == order.orderId)) {
          _queue = [order, ..._queue];
        }
      });
      _showError(error.message);
      unawaited(_refresh());
    } finally {
      _serving.remove(order.orderId);
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
      builder: (_) => _CancelDialog(
        orderId: order.orderId,
        // By name, never ordinal (rule 5).
        alreadyMade: order.status == 'Ready',
      ),
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
    final tabLabels = [
      l10n.tabWithCount(l10n.queueTab, _queue.length),
      l10n.tabWithCount(l10n.handoverTab, _handovers.length),
    ];
    final tabs = measureTabLabels(
      context,
      tabLabels,
      MediaQuery.sizeOf(context).width,
    );

    return ExitConfirmation(
      // A landing screen: nothing sits beneath it in the stack, so back
      // would otherwise close the app outright.
      child: Scaffold(
        appBar: AppBar(
          // The design's top bar, as on Home — the other landing screen: the
          // lockup at the start. It is decorative, so the bar carries the
          // screen's name for screen readers. Scaled down rather than clipped
          // when the count and three actions leave it less than its width on
          // a 320dp phone.
          title: Semantics(
            header: true,
            label: l10n.queueTitle,
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: BrandLockup(width: Dimens.lockupBar),
            ),
          ),
          actions: [
            // Staff drink too, and had no way into the composer at all — the
            // queue is their home screen and nothing linked out of it.
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: l10n.orderForMyself,
              onPressed: _orderForMyself,
            ),
            const NotificationBell(),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.settings,
              onPressed: () => context.push(Routes.settings),
            ),
          ],
          // Colours come from the theme's TabBarTheme: primary label, muted
          // unselected label, blue indicator — all readable on the white bar.
          // Each tab says how many it holds (pending cards included: they are
          // on screen, and still the staff member's until the window closes).
          // Scrolls rather than fading a label cut mid-word when the two do
          // not fit side by side, and grows with the text rather than
          // clipping it.
          bottom: TabBar(
            controller: _tabController,
            isScrollable: !tabs.fit,
            tabAlignment: tabs.fit ? null : TabAlignment.start,
            tabs: [
              for (final label in tabLabels)
                Tab(text: label, height: tabs.height),
            ],
          ),
        ),

        body: Column(
          children: [
            // Notices above the tabs, capped and scrolling on their own, so
            // however many stack up the queue below keeps its room.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.sizeOf(context).height *
                    Dimens.noticeAreaMaxFraction,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Staff change their password too, and land here after.
                    if (ref.watch(sessionNotRefreshedProvider))
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          Dimens.space4,
                          Dimens.space3,
                          Dimens.space4,
                          0,
                        ),
                        child: InlineBanner(
                          tone: BannerTone.warning,
                          title: l10n.sessionNotRefreshed,
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: l10n.dismiss,
                            onPressed: () => ref
                                .read(authControllerProvider.notifier)
                                .acknowledgeSessionNotRefreshed(),
                          ),
                        ),
                      ),
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
                              ? l10n.preparedWithShortages(
                                  outcome.shortageNames!,
                                )
                              : l10n.selfOrderCompleted(outcome.orderId),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: l10n.dismiss,
                            onPressed: () =>
                                setState(() => _selfOrderOutcome = null),
                          ),
                        ),
                      ),
                    // A poll that fails once something is on screen keeps it there —
                    // and says so, rather than freezing looking live while new orders
                    // never arrive (§8.1: a stale queue is worse than a chatty one).
                    if (_errorMessage != null &&
                        (_queue.isNotEmpty || _handovers.isNotEmpty))
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          Dimens.space4,
                          Dimens.space3,
                          Dimens.space4,
                          0,
                        ),
                        child: InlineBanner(
                          tone: BannerTone.warning,
                          title: l10n.couldNotRefreshTitle,
                          body: _loadedAt == null
                              ? _errorMessage
                              : l10n.couldNotRefreshBody(
                                  Formatters.timeOfDay(
                                    _loadedAt!.toUtc(),
                                    Localizations.localeOf(context)
                                        .toLanguageTag(),
                                  ),
                                ),
                          action: TextButton(
                            onPressed: () => unawaited(_refresh()),
                            child: Text(l10n.retry),
                          ),
                        ),
                      ),
                    for (final served in _servedShortages)
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          Dimens.space4,
                          Dimens.space3,
                          Dimens.space4,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    l10n.servedWithShortage(
                                      Formatters.isolate(served.name),
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  tooltip: l10n.dismiss,
                                  onPressed: () => setState(
                                    () => _servedShortages.removeWhere(
                                      (s) => s.orderId == served.orderId,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            ShortageWarnings(warnings: served.warnings),
                          ],
                        ),
                      ),
                  ],
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
                // A made drink nobody collects has to leave the list somehow;
                // the server re-books it as waste, and the dialog says so.
                onCancel: _cancel,
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
  const _CancelDialog({required this.orderId, required this.alreadyMade});

  final int orderId;

  /// A Ready order: its consumption is re-booked as waste.
  final bool alreadyMade;

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

    // The buttons say what they do. "Cancel" beside "Confirm" in a dialog
    // about cancelling left it unclear which one cancelled the order.
    return AlertDialog(
      title: Text(l10n.cancelOrderTitle(widget.orderId)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.alreadyMade) ...[
            Text(l10n.cancelReadyWaste),
            const SizedBox(height: Dimens.space3),
          ],
          TextField(
            controller: _controller,
            decoration: InputDecoration(labelText: l10n.cancelReason),
            autofocus: true,
            maxLines: 2,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.keepOrder),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          style: TextButton.styleFrom(foregroundColor: BrandColors.danger),
          child: Text(l10n.cancelWithReason),
        ),
      ],
    );
  }
}
