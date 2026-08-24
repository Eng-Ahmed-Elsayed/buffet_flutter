/// What placing a staff member's own order did.
///
/// A staff self-order is made and handed over in the same call — they are
/// standing at the machine — so it arrives back at the queue already
/// `Completed`. There is no status screen to send them to and nothing to poll,
/// which makes this the only confirmation the order ever gets.
class SelfOrderOutcome {
  const SelfOrderOutcome({required this.orderId, this.shortageNames});

  final int orderId;

  /// Items that went short, already joined for display by the server.
  ///
  /// **Not a failure**: the drink was made and the ledger written. It means
  /// physical and recorded stock have drifted, which an admin reconciles.
  final String? shortageNames;

  bool get hasShortages => shortageNames != null && shortageNames!.isNotEmpty;
}
