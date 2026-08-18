import 'package:json_annotation/json_annotation.dart';

part 'catalogue_models.g.dart';

/// Mirrors `CatalogueItemDto` in ApiContracts.cs.
@JsonSerializable(createToJson: false)
class CatalogueItemDto {
  const CatalogueItemDto({
    required this.itemId,
    required this.nameAr,
    required this.nameEn,
    required this.category,
    required this.unit,
    required this.imageUrl,
    required this.inStock,
    required this.hasOwnStock,
    required this.ownServingsLeft,
    required this.variants,
  });

  factory CatalogueItemDto.fromJson(Map<String, dynamic> json) =>
      _$CatalogueItemDtoFromJson(json);

  final int itemId;
  final String nameAr;
  final String nameEn;
  final String category;

  /// Admin-entered and in whatever language it was typed. Always bidi-isolated
  /// when rendered next to a number (§2.4).
  final String unit;

  /// Relative — resolve against the API host. A `404` means "use the fallback",
  /// not an error: the uploads folder is not covered by database backups.
  final String? imageUrl;

  /// Company stock. **Never disables a control** — shortages warn only.
  final bool inStock;

  /// True when the signed-in employee owns some of this item. Drives the violet
  /// marking and whether the "from my materials" toggle appears at all.
  final bool hasOwnStock;

  final int ownServingsLeft;

  /// Empty for drinks made only one way, so the client shows the selector only
  /// when there is a choice to make.
  final List<VariantDto> variants;
}

/// Mirrors `VariantDto` in ApiContracts.cs.
@JsonSerializable(createToJson: false)
class VariantDto {
  const VariantDto({
    required this.variantId,
    required this.nameAr,
    required this.nameEn,
    required this.isDefault,
  });

  factory VariantDto.fromJson(Map<String, dynamic> json) =>
      _$VariantDtoFromJson(json);

  final int variantId;
  final String nameAr;
  final String nameEn;
  final bool isDefault;
}

/// Mirrors `CatalogueResponse` in ApiContracts.cs.
///
/// Bundled deliberately: a phone on office wifi should not need four requests
/// to draw one screen.
@JsonSerializable(createToJson: false)
class CatalogueResponse {
  const CatalogueResponse({
    required this.drinks,
    required this.sugars,
    required this.extras,
    required this.locations,
    required this.usual,
  });

  factory CatalogueResponse.fromJson(Map<String, dynamic> json) =>
      _$CatalogueResponseFromJson(json);

  final List<CatalogueItemDto> drinks;
  final List<CatalogueItemDto> sugars;
  final List<CatalogueItemDto> extras;
  final List<LocationDto> locations;

  /// The caller's last order, for a one-tap repeat. Null when they have never
  /// ordered.
  final UsualOrderDto? usual;
}

/// Mirrors `LocationDto` in ApiContracts.cs.
///
/// The managed list is a **suggestion**: an unlisted place must never block an
/// order, so the composer sends `locationText` when the user types their own.
@JsonSerializable(createToJson: false)
class LocationDto {
  const LocationDto({
    required this.locationId,
    required this.nameAr,
    required this.kind,
  });

  factory LocationDto.fromJson(Map<String, dynamic> json) =>
      _$LocationDtoFromJson(json);

  final int locationId;
  final String nameAr;
  final String kind;
}

/// Mirrors `UsualOrderDto` in ApiContracts.cs.
@JsonSerializable(createToJson: false)
class UsualOrderDto {
  const UsualOrderDto({required this.summary, required this.lines});

  factory UsualOrderDto.fromJson(Map<String, dynamic> json) =>
      _$UsualOrderDtoFromJson(json);

  /// Human-readable, server-composed. Rendered as-is.
  final String summary;

  /// The full lines, **including which jar each component came from**, so one
  /// tap refills the composer exactly.
  final List<OrderLineDto> lines;
}

/// Mirrors `OrderLineDto` in ApiContracts.cs.
///
/// The `*FromOwn` booleans are computed **relative to the caller**, which is
/// why staff get their own DTO naming sources instead (`StaffOrderLineDto`).
@JsonSerializable()
class OrderLineDto {
  const OrderLineDto({
    required this.drinkItemId,
    required this.drinkNameAr,
    required this.sugarSpoons,
    required this.variantId,
    required this.sugarItemId,
    required this.extraItemIds,
    required this.lineNote,
    required this.drinkFromOwn,
    required this.sugarFromOwn,
    required this.ownExtraItemIds,
  });

  factory OrderLineDto.fromJson(Map<String, dynamic> json) =>
      _$OrderLineDtoFromJson(json);

  final int drinkItemId;
  final String drinkNameAr;

  /// Zero is a valid, explicit choice — "no sugar" — and the server
  /// distinguishes it from unspecified.
  final int sugarSpoons;

  final int? variantId;

  /// Sugar must be named explicitly; the service only auto-resolves it when
  /// exactly one active sugar exists.
  final int? sugarItemId;

  final List<int> extraItemIds;
  final String? lineNote;
  final bool drinkFromOwn;
  final bool sugarFromOwn;
  final List<int> ownExtraItemIds;

  Map<String, dynamic> toJson() => _$OrderLineDtoToJson(this);

  OrderLineDto copyWith({
    int? drinkItemId,
    String? drinkNameAr,
    int? sugarSpoons,
    int? Function()? variantId,
    int? Function()? sugarItemId,
    List<int>? extraItemIds,
    String? Function()? lineNote,
    bool? drinkFromOwn,
    bool? sugarFromOwn,
    List<int>? ownExtraItemIds,
  }) => OrderLineDto(
    drinkItemId: drinkItemId ?? this.drinkItemId,
    drinkNameAr: drinkNameAr ?? this.drinkNameAr,
    sugarSpoons: sugarSpoons ?? this.sugarSpoons,
    variantId: variantId != null ? variantId() : this.variantId,
    sugarItemId: sugarItemId != null ? sugarItemId() : this.sugarItemId,
    extraItemIds: extraItemIds ?? this.extraItemIds,
    lineNote: lineNote != null ? lineNote() : this.lineNote,
    drinkFromOwn: drinkFromOwn ?? this.drinkFromOwn,
    sugarFromOwn: sugarFromOwn ?? this.sugarFromOwn,
    ownExtraItemIds: ownExtraItemIds ?? this.ownExtraItemIds,
  );
}
