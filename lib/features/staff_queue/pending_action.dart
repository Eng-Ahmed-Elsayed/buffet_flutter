/// A staff action that has been tapped but not yet sent.
///
/// The undo here is a **deferred send**, not a compensating one: `/ready` is
/// the only path that writes ledger rows and the API has no un-ready endpoint,
/// so there is no way back once it fires. Undo therefore has to happen
/// *before* the call, which means holding the action for a moment first.
class PendingAction {
  const PendingAction({
    required this.kind,
    required this.deliverNow,
    required this.deadline,
  });

  final PendingActionKind kind;

  /// Ready and handed over in one motion — the common case at the counter.
  /// Meaningless for [PendingActionKind.complete].
  final bool deliverNow;

  /// When the send fires, as an **absolute instant** rather than a remaining
  /// duration.
  ///
  /// The countdown derives "how long left" from `DateTime.now()`, so a dropped
  /// frame, a rebuild from the 10s poll, or a spell in the background cannot
  /// make the bar disagree with the timer that will actually fire.
  final DateTime deadline;

  Duration remainingFrom(DateTime now) {
    final left = deadline.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

enum PendingActionKind { ready, complete }
