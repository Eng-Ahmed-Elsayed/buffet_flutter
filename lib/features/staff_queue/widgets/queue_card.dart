import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/api/api_config.dart';
import '../../../data/models/staff_models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/formatters.dart';
import '../../../shared/widgets/banners.dart';
import '../../../shared/widgets/source_chip.dart';
import '../../../theme/brand_colors.dart';
import '../../../theme/dimens.dart';
import '../../../theme/motion.dart';
import '../pending_action.dart';

/// One order in the staff queue.
///
/// The card's whole job is saying **which jar to reach for**: every line names
/// its source owner, in violet when it is someone's personal stock. There is no
/// sugar *name* to show — `sugarNameAr` is always null — so the card shows the
/// spoon count and the source instead (§8.1).
class QueueCard extends StatelessWidget {
  const QueueCard({
    required this.order,
    required this.warnings,
    required this.onMarkReady,
    required this.onComplete,
    required this.onCancel,
    this.pending,
    this.onUndo,
    super.key,
  });

  final StaffOrderDto order;

  /// Warnings from a recent serve. A populated list is **not** a failure — the
  /// drink was made and the shortfall is for an admin to reconcile.
  final List<StockWarningDto>? warnings;

  final Future<void> Function(StaffOrderDto, {required bool deliverNow})?
  onMarkReady;
  final Future<void> Function(StaffOrderDto)? onComplete;

  /// Cancels with a reason. Null on the handover list, where the drink is
  /// already made and cancelling is the wrong remedy.
  final Future<void> Function(StaffOrderDto)? onCancel;

  /// Non-null while this order's action is waiting out its undo window.
  ///
  /// The card stays in the list and keeps its footprint while pending. It used
  /// to vanish and put its undo in a SnackBar, which broke badly under a rush:
  /// ScaffoldMessenger *queues* snackbars rather than replacing them, so five
  /// quick taps showed five bars one after another, each still offering to undo
  /// an order that had already been served. The affordance belongs on the card
  /// it acts on.
  final PendingAction? pending;

  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final minutes = Formatters.minutesFromSeconds(order.waitingSeconds);
    final isAgeing = minutes >= 5;
    final hasWarnings = warnings != null && warnings!.isNotEmpty;
    final isPending = pending != null;

    return Container(
      padding: const EdgeInsetsDirectional.all(Dimens.space4),
      decoration: BoxDecoration(
        color: BrandColors.surface,
        border: Border.all(
          // Pending reads as pending by weight as well as by colour: a thicker
          // green edge, plus dimmed content, plus an icon, plus a label.
          // Colour is never the only signal.
          color: isPending
              ? BrandColors.ok
              : hasWarnings
              ? BrandColors.warning
              : BrandColors.brandLight,
          width: isPending ? Dimens.borderSelected : Dimens.borderHairline,
        ),
        borderRadius: BorderRadius.circular(Dimens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Whose drink this is leads, because that is what the
                    // person making it needs. On a guest order the recipient is
                    // the guest, and the colleague who ordered it drops to a
                    // secondary line rather than disappearing — accountability
                    // stays with the requester.
                    Text(
                      // A person's name is user data in an unknown script.
                      Formatters.isolate(
                        order.onBehalfOfName ?? order.requesterDisplayName,
                      ),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (order.onBehalfOfName != null)
                      Text(
                        l10n.orderedBy(
                          Formatters.isolate(order.requesterDisplayName),
                        ),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    Text(
                      // Each half isolated SEPARATELY, not the joined string:
                      // department and location have independent directions
                      // (observed live: "المالية · meeting room 1"), and one
                      // isolate around the pair would still let the bidi
                      // algorithm reorder them around the separator.
                      //
                      // locationText is optional, so the separator is only
                      // drawn when there are two things to separate —
                      // otherwise the card showed a dangling "المالية · ".
                      [
                        if (order.department.trim().isNotEmpty)
                          Formatters.isolate(order.department),
                        if (order.locationText.trim().isNotEmpty)
                          Formatters.isolate(order.locationText),
                      ].join(' · '),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (order.onBehalfOfName != null) ...[
                // brandLight, deliberately NOT accent: violet means "from my
                // own jar" everywhere and must not pick up a second meaning.
                const _GuestChip(),
                const SizedBox(width: Dimens.space2),
              ],
              _AgeingBadge(minutes: minutes, isAgeing: isAgeing),
            ],
          ),

          const SizedBox(height: Dimens.space3),
          const Divider(),
          const SizedBox(height: Dimens.space3),

          for (final line in order.lines) ...[
            _LineDetails(line: line),
            if (line != order.lines.last) const SizedBox(height: Dimens.space4),
          ],

          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: Dimens.space3),
            _NoteBlock(note: order.notes),
          ],

          if (hasWarnings) ...[
            const SizedBox(height: Dimens.space3),
            _ShortageWarnings(warnings: warnings!),
          ],

          const SizedBox(height: Dimens.space4),
          AnimatedSwitcher(
            // fast, not base: this acknowledges a press rather than moving the
            // user somewhere.
            duration: Motion.of(context, Motion.fast),
            switchInCurve: Motion.easeSoft,
            switchOutCurve: Motion.easeSoft,
            child: isPending
                ? _PendingBar(
                    key: ValueKey('pending-${order.orderId}'),
                    orderId: order.orderId,
                    pending: pending!,
                    onUndo: onUndo,
                  )
                : _Actions(
                    key: ValueKey('actions-${order.orderId}'),
                    order: order,
                    onMarkReady: onMarkReady,
                    onComplete: onComplete,
                    onCancel: onCancel,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Marks an order placed on behalf of a visitor.
class _GuestChip extends StatelessWidget {
  const _GuestChip();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Dimens.space2,
        vertical: Dimens.space1,
      ),
      decoration: BoxDecoration(
        color: BrandColors.brandLight,
        borderRadius: BorderRadius.circular(Dimens.radiusSm),
      ),
      child: Text(
        l10n.guestOrder,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: BrandColors.brand),
      ),
    );
  }
}

class _AgeingBadge extends StatelessWidget {
  const _AgeingBadge({required this.minutes, required this.isAgeing});

  final int minutes;
  final bool isAgeing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Dimens.space2,
        vertical: Dimens.space1,
      ),
      decoration: BoxDecoration(
        color: isAgeing ? BrandColors.warningSurface : BrandColors.page,
        borderRadius: BorderRadius.circular(Dimens.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 13,
            color: isAgeing ? BrandColors.warning : BrandColors.muted,
          ),
          const SizedBox(width: Dimens.space1),
          Text(
            l10n.waitingMinutes(minutes),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isAgeing ? BrandColors.warning : BrandColors.muted,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _LineDetails extends StatelessWidget {
  const _LineDetails({required this.line});

  final StaffOrderLineDto line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A Wrap, not a Row: the drink name and its preparation together were
        // wider than a 320dp card at the larger text scales — by 210dp at 2x —
        // and an unbounded Row has nowhere to put the excess but off the edge.
        // The preparation drops to its own line instead.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Dimens.space2,
          children: [
            Text(
              // Arabic by contract: StaffOrderLineDto carries only *NameAr —
              // there are no English fields on the staff wire, unlike
              // CatalogueItemDto. Deliberately NOT joined against /catalogue
              // to translate: staff work in Arabic, and fetching the whole
              // employee catalogue on every queue render for a cosmetic name
              // swap is the wrong trade. Revisit if the staff DTO gains
              // NameEn.
              line.drinkNameAr,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (line.variantNameAr case final String variant)
              Text(variant, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: Dimens.space2),

        Wrap(
          spacing: Dimens.space2,
          runSpacing: Dimens.space2,
          children: [
            // Which jar the drink itself comes from — the most important line
            // on the card.
            SourceChip(label: l10n.drink, ownerName: line.drinkSourceOwnerName),

            // sugarNameAr is always null, so this is the spoon count plus its
            // source — never a sugar name.
            SourceChip(
              label: l10n.spoons(line.sugarSpoons),
              ownerName: line.sugarSourceOwnerName,
            ),

            for (final extra in line.extraSources)
              SourceChip(label: extra.nameAr, ownerName: extra.sourceOwnerName),

            // An extra with no matching source entry still gets shown.
            for (final name in line.extraNamesAr)
              if (!line.extraSources.any((s) => s.nameAr == name))
                DetailChip(label: name),
          ],
        ),

        if (line.lineNote != null && line.lineNote!.isNotEmpty) ...[
          const SizedBox(height: Dimens.space2),
          _NoteBlock(note: line.lineNote!),
        ],
      ],
    );
  }
}

class _NoteBlock extends StatelessWidget {
  const _NoteBlock({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Dimens.space3,
        vertical: Dimens.space2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.page,
        borderRadius: BorderRadius.circular(Dimens.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.sticky_note_2_outlined,
            size: 15,
            color: BrandColors.muted,
          ),
          const SizedBox(width: Dimens.space2),
          Expanded(
            child: Text(
              note,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: BrandColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shortages that came back on a **`200`** after serving.
///
/// Presented as information, not failure: the drink was made and handed over.
class _ShortageWarnings extends StatelessWidget {
  const _ShortageWarnings({required this.warnings});

  final List<StockWarningDto> warnings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        for (final warning in warnings)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: Dimens.space2),
            child: InlineBanner(
              tone: BannerTone.warning,
              title: l10n.shortageTitle,
              body: [
                warning.nameAr,
                if (warning.ownerDisplayName.isNotEmpty)
                  l10n.fromJarOf(Formatters.isolate(warning.ownerDisplayName)),
                // Quantity and unit isolated — the unit is admin-entered.
                l10n.shortfallAmount(
                  Formatters.quantity(warning.shortfall, warning.unit),
                ),
                l10n.shortageBody,
              ].join('\n'),
            ),
          ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.order,
    required this.onMarkReady,
    required this.onComplete,
    required this.onCancel,
    super.key,
  });

  final StaffOrderDto order;
  final Future<void> Function(StaffOrderDto, {required bool deliverNow})?
  onMarkReady;
  final Future<void> Function(StaffOrderDto)? onComplete;
  final Future<void> Function(StaffOrderDto)? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // The handover list: the drink is already made and stock already deducted,
    // so the only action left is stamping it as collected.
    if (onComplete != null) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () => onComplete!(order),
          child: Text(l10n.markDelivered),
        ),
      );
    }

    if (onMarkReady == null) return const SizedBox.shrink();

    return Column(
      children: [
        _readyRow(context, l10n),
        if (onCancel != null) ...[
          const SizedBox(height: Dimens.space2),
          // Set apart from the two constructive actions above rather than
          // sitting flush against them: a destructive action adjacent to the
          // one you reach for fifty times a shift is a mis-tap waiting to
          // happen.
          const Divider(height: Dimens.space3),
          // The ONE staff action that warrants a dialog (§8.1): it takes a
          // reason, and unlike Ready it cannot be undone by simply not
          // sending it. Everything else here is one tap with an undo window.
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => onCancel!(order),
              style: TextButton.styleFrom(foregroundColor: BrandColors.danger),
              child: Text(l10n.cancelWithReason),
            ),
          ),
        ],
      ],
    );
  }

  /// The two ways a drink leaves the queue, stacked rather than side by side.
  ///
  /// They used to share a row, which forced the primary label to ellipsise on
  /// a narrow handset — so the most-used control on the busiest screen in the
  /// app read as "ready and deli…". Full width each, primary first, and the
  /// label always legible.
  ///
  /// `deliverNow` stays the primary: it is the common case at the counter,
  /// ready and handed over in one motion.
  ///
  /// NEITHER button is ever disabled on a stock reading: /ready returns 200
  /// with warnings, never 400 (§8.1).
  Widget _readyRow(BuildContext context, AppLocalizations l10n) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => onMarkReady!(order, deliverNow: true),
            child: Text(l10n.readyAndDelivered),
          ),
        ),
        const SizedBox(height: Dimens.space2),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => onMarkReady!(order, deliverNow: false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: BrandColors.brand),
              minimumSize: const Size(Dimens.minTarget, Dimens.controlHeight),
            ),
            child: Text(l10n.markReady),
          ),
        ),
      ],
    );
  }
}

/// The undo affordance, in the card, for one pending action.
///
/// Replaces the SnackBar that used to carry it. Two clocks drive it, on
/// purpose: a smooth [AnimationController] for the draining bar, and a coarse
/// one-second [Timer] for the digit. Rebuilding a card carrying a dozen chips
/// sixty times a second to move a number that changes five times is waste, and
/// the two are seeded from the same absolute deadline so they cannot disagree.
class _PendingBar extends StatefulWidget {
  const _PendingBar({
    required this.orderId,
    required this.pending,
    required this.onUndo,
    super.key,
  });

  final int orderId;
  final PendingAction pending;
  final VoidCallback? onUndo;

  @override
  State<_PendingBar> createState() => _PendingBarState();
}

class _PendingBarState extends State<_PendingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _tick;
  int _secondsLeft = 0;

  /// The full window this action was given, recovered from the deadline.
  ///
  /// Needed because the window is longer under a screen reader, and the bar has
  /// to know what "full" means before it can show how much is left.
  late final Duration _window;

  @override
  void initState() {
    super.initState();

    final remaining = widget.pending.remainingFrom(DateTime.now());
    _window = remaining > ApiConfig.undoWindow
        ? ApiConfig.undoWindowAccessible
        : ApiConfig.undoWindow;
    _secondsLeft =
        remaining.inSeconds + (remaining.inMilliseconds % 1000 > 0 ? 1 : 0);

    _controller = AnimationController(vsync: this, duration: _window);
    // Seeded from where the window actually is, not from zero: a rebuild driven
    // by the ten-second poll must not restart the bar and promise time the
    // timer will not honour.
    _controller.value = _window.inMilliseconds == 0
        ? 1
        : 1 - (remaining.inMilliseconds / _window.inMilliseconds);
    _controller.forward();

    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = widget.pending.remainingFrom(DateTime.now());
      final seconds = left.inSeconds + (left.inMilliseconds % 1000 > 0 ? 1 : 0);
      if (seconds != _secondsLeft) setState(() => _secondsLeft = seconds);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Holds the countdown while a finger is down.
  ///
  /// Someone reading this card with a screen reader is not racing a clock, and
  /// neither is someone who has just put a thumb on it to steady the phone.
  void _pause() => _controller.stop();

  void _resume() {
    final left = widget.pending.remainingFrom(DateTime.now());
    if (left == Duration.zero) return;
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isReady = widget.pending.kind == PendingActionKind.ready;
    final label = isReady ? l10n.servingOrder : l10n.handingOverOrder;
    // Reduced motion still gets a countdown — it is state, not decoration —
    // but it steps rather than sweeps, so nothing moves continuously.
    final stepped = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      liveRegion: true,
      label: l10n.undoWindowSemantics(widget.orderId, _secondsLeft),
      child: Listener(
        onPointerDown: (_) => _pause(),
        onPointerUp: (_) => _resume(),
        onPointerCancel: (_) => _resume(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(Dimens.handleRadius),
              child: SizedBox(
                height: Dimens.borderSelected,
                child: ColoredBox(
                  color: BrandColors.okSurface,
                  child: stepped
                      ? _SteppedCountdown(
                          total: _window.inSeconds,
                          remaining: _secondsLeft,
                        )
                      : AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => Align(
                            // Directional, so the bar drains from the start
                            // edge in both scripts. LinearProgressIndicator
                            // anchors LTR and reads backwards under RTL for a
                            // draining semantic.
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: (1 - _controller.value).clamp(
                              0.0,
                              1.0,
                            ),
                            child: const ColoredBox(
                              color: BrandColors.ok,
                              child: SizedBox(
                                height: Dimens.borderSelected,
                                width: double.infinity,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: Dimens.space2),
            Row(
              children: [
                const Icon(
                  Icons.local_cafe_outlined,
                  size: 16,
                  color: BrandColors.ok,
                ),
                const SizedBox(width: Dimens.space2),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: BrandColors.ok),
                  ),
                ),
                if (widget.onUndo != null)
                  TextButton(
                    onPressed: widget.onUndo,
                    style: TextButton.styleFrom(
                      foregroundColor: BrandColors.ok,
                      // Deliberately oversized. This is the affordance whose
                      // failure is expensive, and it is pressed in a hurry.
                      minimumSize: const Size(
                        Dimens.minTarget * 2,
                        Dimens.controlHeight,
                      ),
                    ),
                    child: Text(l10n.undoCountdown(_secondsLeft)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The countdown as discrete segments, for reduced motion.
///
/// One segment per second, extinguishing on the same one-second tick that
/// drives the digit. Nothing moves; the state is still legible.
class _SteppedCountdown extends StatelessWidget {
  const _SteppedCountdown({required this.total, required this.remaining});

  final int total;
  final int remaining;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: ColoredBox(
              color: i < remaining ? BrandColors.ok : BrandColors.okSurface,
              child: const SizedBox(height: Dimens.borderSelected),
            ),
          ),
          if (i < total - 1) const SizedBox(width: 1),
        ],
      ],
    );
  }
}
