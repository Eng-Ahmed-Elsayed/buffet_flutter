import '../../data/models/order_models.dart';

/// Notices the caller's orders reaching Ready or Cancelled between two looks at
/// the order list.
///
/// Fed from Home, which stays mounted beneath every tab and every pushed screen
/// and polls the list while the app is in the foreground. The alert used to be
/// fired by the tracking screen alone, so it chimed only for someone already
/// looking at that order, and never for someone waiting on another tab.
class OrderStatusTracker {
  Map<int, OrderStatus>? _seen;

  /// The orders that reached Ready or Cancelled since the last look.
  ///
  /// The first look after [forget] only records: an order that was already
  /// Ready when the user came back to the app is not news, and they are
  /// looking at it. Orders not seen before are recorded, not announced.
  List<OrderSummaryDto> changed(List<OrderSummaryDto> orders) {
    final seen = _seen;
    _seen = {for (final o in orders) o.orderId: o.orderStatus};
    if (seen == null) return const [];
    return [
      for (final o in orders)
        // Compared by name through the enum, never by ordinal (rule 5).
        if (o.orderStatus == OrderStatus.ready ||
            o.orderStatus == OrderStatus.cancelled)
          if (seen[o.orderId] case final OrderStatus before
              when before != o.orderStatus)
            o,
    ];
  }

  /// Drops what was seen, so the next look starts afresh. Called when the app
  /// leaves the foreground: a change found on return is shown by the screen
  /// itself, and a push (Android) will already have announced it.
  void forget() => _seen = null;
}
