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

/// Pickup or delivery (§7.8), sent and read **by name**, like every enum on
/// this API.
enum Fulfilment {
  /// The requester collects it from the kitchen.
  pickup('Pickup'),

  /// Staff carry it to the location.
  delivery('Delivery');

  const Fulfilment(this.wire);

  final String wire;

  /// Null for null, and for anything unrecognised: an order placed before the
  /// choice existed is **neutral**, neither "come and get it" nor "on its way".
  static Fulfilment? fromWire(String? value) {
    for (final mode in values) {
      if (mode.wire == value) return mode;
    }
    return null;
  }
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
    this.saveAsFavourite = false,
    this.favouriteName,
    this.fromFavouriteId,
    this.fulfilment,
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

  /// Save these lines as a favourite once the order is placed, so "order this
  /// again" needs no second screen.
  ///
  /// **Best-effort, and never fails the order** — the drink is already made by
  /// the time it is written. Ignored on an idempotent retry, so resending after
  /// a dropped response cannot leave two copies of the same favourite.
  final bool saveAsFavourite;

  /// What to call it. Ignored unless [saveAsFavourite] is set; **null means
  /// "name it after the drinks"**, which the server does including the
  /// preparation.
  final String? favouriteName;

  /// The favourite this order was replayed from, when it was.
  ///
  /// Only stamps that favourite as recently used — it does not affect what is
  /// ordered, which comes from [lines] as on any other order.
  final int? fromFavouriteId;

  /// `"Pickup"` or `"Delivery"` (§7.8). Omitted, the server infers it from
  /// whether a location resolves, as older builds relied on. `Delivery` with
  /// no location is a `400`.
  final String? fulfilment;

  Map<String, dynamic> toJson() => _$PlaceOrderApiRequestToJson(this);
}

/// Mirrors `PlaceOrderResponse` in ApiContracts.cs.
///
/// `201` with `duplicate: false` means created; `200` with `duplicate: true`
/// means the retry matched an existing order. **Both are success** and show the
/// same confirmation.
@JsonSerializable(createToJson: false)
class PlaceOrderResponse {
  const PlaceOrderResponse({
    required this.orderId,
    required this.duplicate,
    this.autoServed = false,
    this.shortageNames,
    this.favouriteId,
  });

  factory PlaceOrderResponse.fromJson(Map<String, dynamic> json) =>
      _$PlaceOrderResponseFromJson(json);

  final int orderId;
  final bool duplicate;

  /// The order was made and handed over in the same call.
  ///
  /// True only for a staff member's own order — they are standing at the
  /// machine, so there is no queue to wait in. The order is already
  /// `Completed`, so **do not open a status screen to poll it**: there is
  /// nothing left to watch.
  ///
  /// Defaults to false so a server that predates the field is read as no,
  /// which is the behaviour every other role gets anyway.
  @JsonKey(defaultValue: false)
  final bool autoServed;

  /// Items that went short while auto-serving, already joined for display.
  ///
  /// **Not a failure**: the drink was made and the ledger written. It means
  /// physical and recorded stock have drifted, which an admin reconciles.
  final String? shortageNames;

  /// The favourite created from this order, when one was asked for and saved.
  ///
  /// **Null is not an error.** It is null both when none was requested and when
  /// saving failed — a full list, or an item retired since. The order stands
  /// either way, so never interrupt a successful order over it.
  final int? favouriteId;
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
    this.startedAtUtc,
    this.fulfilment,
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

  /// When staff began making it (§7.3). **Null both before they start and when
  /// they never did**: staff can serve straight from Pending, so a Ready or
  /// Completed order can have none. Never backfilled.
  final DateTime? startedAtUtc;

  /// `"Pickup"`, `"Delivery"`, or null for an order placed before the choice
  /// existed. Read [fulfilmentMode].
  final String? fulfilment;

  /// Null means neutral wording.
  Fulfilment? get fulfilmentMode => Fulfilment.fromWire(fulfilment);

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
