import 'package:json_annotation/json_annotation.dart';

import 'catalogue_models.dart';

part 'order_models.g.dart';

/// The order lifecycle: `Pending → InProgress → Ready → Completed`, plus
/// `Cancelled`.
///
/// **The enum ordinals on the server are not in workflow order** (`Ready = 4`),
/// so this type exists to make comparing by integer impossible. The wire value
/// is always the string name, in both directions.
enum OrderStatus {
  pending('Pending'),
  inProgress('InProgress'),

  /// The drink was **physically made** and stock was deducted. This is the
  /// "come and collect it" moment and deserves the loudest visual state — not
  /// [completed].
  ready('Ready'),

  /// Handed over. Quieter than [ready] by design.
  completed('Completed'),

  cancelled('Cancelled');

  const OrderStatus(this.wire);

  /// The exact string the API sends and expects.
  final String wire;

  /// Parses by name. An unrecognised status maps to [pending] rather than
  /// throwing: a new server-side state should not crash a shipped client.
  static OrderStatus fromWire(String value) => OrderStatus.values.firstWhere(
    (s) => s.wire == value,
    orElse: () => OrderStatus.pending,
  );

  /// Cancellation is **pending-only** and ownership-checked. The action is
  /// hidden once the status leaves [pending], rather than shown disabled.
  bool get isCancellable => this == OrderStatus.pending;

  /// Still on its way to being made — [pending] or [inProgress].
  ///
  /// **Not the same as "still changing".** A [ready] order is not `isLive`
  /// (the drink exists) but it has not finished moving: handover takes it to
  /// [completed]. Use [isSettled] to decide whether to stop polling.
  bool get isLive =>
      this == OrderStatus.pending || this == OrderStatus.inProgress;

  /// Whether this status can never change again.
  ///
  /// Only [completed] and [cancelled] are terminal. Polling stops here and
  /// nowhere earlier — stopping at [ready] would leave an employee watching
  /// "your drink is ready" forever, never seeing it turn to collected.
  bool get isSettled =>
      this == OrderStatus.completed || this == OrderStatus.cancelled;
}

/// Mirrors `PlaceOrderApiRequest` in ApiContracts.cs.
@JsonSerializable(createFactory: false, includeIfNull: false)
class PlaceOrderApiRequest {
  const PlaceOrderApiRequest({
    required this.lines,
    this.notes,
    this.locationId,
    this.locationText,
    this.onBehalfOfName,
    this.idempotencyKey,
  });

  final List<OrderLineDto> lines;
  final String? notes;

  /// Sent when the user picked a managed suggestion.
  final int? locationId;

  /// Sent when the user typed their own place. An unlisted location must never
  /// block an order (§7.1).
  final String? locationText;

  final String? onBehalfOfName;

  /// **Client-generated, created when the composer opens and kept across
  /// retries** — discarded only once the order is confirmed. A dropped response
  /// on office wifi otherwise becomes a second coffee (§7.2).
  final String? idempotencyKey;

  Map<String, dynamic> toJson() => _$PlaceOrderApiRequestToJson(this);
}

/// Mirrors `PlaceOrderResponse` in ApiContracts.cs.
///
/// `201` with `duplicate: false` means created; `200` with `duplicate: true`
/// means the retry matched an existing order. **Both are success** and show the
/// same confirmation.
@JsonSerializable(createToJson: false)
class PlaceOrderResponse {
  const PlaceOrderResponse({required this.orderId, required this.duplicate});

  factory PlaceOrderResponse.fromJson(Map<String, dynamic> json) =>
      _$PlaceOrderResponseFromJson(json);

  final int orderId;
  final bool duplicate;
}

/// Mirrors `OrderSummaryDto` in ApiContracts.cs.
@JsonSerializable(createToJson: false)
class OrderSummaryDto {
  const OrderSummaryDto({
    required this.orderId,
    required this.status,
    required this.createdAtUtc,
    required this.readyAtUtc,
    required this.handledAtUtc,
    required this.locationText,
    required this.onBehalfOfName,
    required this.notes,
    required this.lines,
  });

  factory OrderSummaryDto.fromJson(Map<String, dynamic> json) =>
      _$OrderSummaryDtoFromJson(json);

  final int orderId;

  /// The raw wire string. Read [orderStatus] instead of comparing this by hand.
  final String status;

  /// UTC. Convert for display; never render raw (§10).
  final DateTime createdAtUtc;
  final DateTime? readyAtUtc;
  final DateTime? handledAtUtc;

  final String locationText;
  final String? onBehalfOfName;
  final String notes;
  final List<OrderLineDto> lines;

  /// Parsed by name, never by ordinal.
  OrderStatus get orderStatus => OrderStatus.fromWire(status);

  /// Mirrors the server-computed `IsReady`, as a getter rather than a field.
  bool get isReady => orderStatus == OrderStatus.ready;
}

/// Mirrors `NotificationDto` in ApiContracts.cs.
@JsonSerializable(createToJson: false)
class NotificationDto {
  const NotificationDto({
    required this.notificationId,
    required this.kind,
    required this.message,
    required this.orderId,
    required this.createdAtUtc,
    required this.isRead,
  });

  factory NotificationDto.fromJson(Map<String, dynamic> json) =>
      _$NotificationDtoFromJson(json);

  final int notificationId;

  /// `OrderReady`, `DeclarationConfirmed`, `DeclarationRejected`, among others.
  final String kind;

  /// Already localised server-side. Rendered as-is.
  final String message;

  final int? orderId;
  final DateTime createdAtUtc;
  final bool isRead;
}
