import 'package:json_annotation/json_annotation.dart';

part 'staff_models.g.dart';

/// Mirrors `StaffOrderDto` in StaffContracts.cs — a queue entry seen from
/// behind the counter.
@JsonSerializable(createToJson: false)
class StaffOrderDto {
  const StaffOrderDto({
    required this.orderId,
    required this.status,
    required this.createdAtUtc,
    required this.readyAtUtc,
    required this.requesterDisplayName,
    required this.department,
    required this.locationText,
    required this.onBehalfOfName,
    required this.notes,
    required this.waitingSeconds,
    required this.lines,
  });

  factory StaffOrderDto.fromJson(Map<String, dynamic> json) =>
      _$StaffOrderDtoFromJson(json);

  final int orderId;

  /// Compared by name via `OrderStatus.fromWire`, never by ordinal.
  final String status;

  final DateTime createdAtUtc;
  final DateTime? readyAtUtc;

  /// Staff need the name, not the username.
  final String requesterDisplayName;

  final String department;
  final String locationText;
  final String? onBehalfOfName;
  final String notes;

  /// Seconds since the order was placed, for the ageing indicator.
  final int waitingSeconds;

  final List<StaffOrderLineDto> lines;
}

/// Mirrors `StaffOrderLineDto` in StaffContracts.cs — one drink to make.
///
/// Unlike the employee's `OrderLineDto`, sources are **named** rather than
/// flattened to "from own" booleans: those are computed relative to the caller,
/// which is meaningless to staff. The queue's whole job is saying which jar to
/// reach for.
@JsonSerializable(createToJson: false)
class StaffOrderLineDto {
  const StaffOrderLineDto({
    required this.drinkItemId,
    required this.drinkNameAr,
    required this.variantNameAr,
    required this.sugarSpoons,
    required this.sugarNameAr,
    required this.extraNamesAr,
    required this.lineNote,
    required this.drinkSourceOwnerName,
    required this.sugarSourceOwnerName,
    required this.extraSources,
  });

  factory StaffOrderLineDto.fromJson(Map<String, dynamic> json) =>
      _$StaffOrderLineDtoFromJson(json);

  final int drinkItemId;
  final String drinkNameAr;
  final String? variantNameAr;
  final int sugarSpoons;

  /// **Always null** — a documented deviation. The card shows the spoon count
  /// and the source owner instead; do not design around a sugar name.
  final String? sugarNameAr;

  final List<String> extraNamesAr;
  final String? lineNote;

  /// **Empty string for company stock**, otherwise the owner's display name.
  /// This is what tells the person making the drink which jar to reach for.
  final String drinkSourceOwnerName;

  final String sugarSourceOwnerName;
  final List<StaffExtraSourceDto> extraSources;
}

/// Mirrors `StaffExtraSourceDto` in StaffContracts.cs.
@JsonSerializable(createToJson: false)
class StaffExtraSourceDto {
  const StaffExtraSourceDto({
    required this.itemId,
    required this.nameAr,
    required this.sourceOwnerName,
  });

  factory StaffExtraSourceDto.fromJson(Map<String, dynamic> json) =>
      _$StaffExtraSourceDtoFromJson(json);

  final int itemId;
  final String nameAr;

  /// Empty string for company stock, otherwise the owner's display name.
  final String sourceOwnerName;
}

/// Mirrors `ServeResultDto` in StaffContracts.cs — the outcome of serving.
///
/// **Warnings ride in the body rather than an error status because shortages
/// never block**: staff need to see them, and the drink was still made. A
/// populated [warnings] on a `200` is success, not failure.
@JsonSerializable(createToJson: false)
class ServeResultDto {
  const ServeResultDto({
    required this.orderId,
    required this.status,
    required this.warnings,
  });

  factory ServeResultDto.fromJson(Map<String, dynamic> json) =>
      _$ServeResultDtoFromJson(json);

  final int orderId;
  final String status;

  /// Empty is the normal case.
  final List<StockWarningDto> warnings;

  bool get hasWarnings => warnings.isNotEmpty;
}

/// Mirrors `StockWarningDto` in StaffContracts.cs.
@JsonSerializable(createToJson: false)
class StockWarningDto {
  const StockWarningDto({
    required this.itemId,
    required this.nameAr,
    required this.ownerDisplayName,
    required this.shortfall,
    required this.unit,
  });

  factory StockWarningDto.fromJson(Map<String, dynamic> json) =>
      _$StockWarningDtoFromJson(json);

  final int itemId;
  final String nameAr;

  /// Empty string for company stock, otherwise whose jar ran short.
  final String ownerDisplayName;

  /// How far below zero the balance went. A positive number.
  final num shortfall;

  /// Admin-entered; bidi-isolated when rendered with [shortfall].
  final String unit;
}

/// Mirrors `CancelOrderRequest` in StaffContracts.cs.
///
/// Cancelling a `Ready` order reverses the consumption and re-books it as
/// waste — the balance is unchanged but nobody is credited with a drink they
/// never received.
@JsonSerializable(createFactory: false, includeIfNull: false)
class CancelOrderRequest {
  const CancelOrderRequest({this.reason});

  final String? reason;

  Map<String, dynamic> toJson() => _$CancelOrderRequestToJson(this);
}
