import 'package:json_annotation/json_annotation.dart';

part 'material_models.g.dart';

/// Mirrors `MyMaterialDto` in ApiContracts.cs.
@JsonSerializable(createToJson: false)
class MyMaterialDto {
  const MyMaterialDto({
    required this.itemId,
    required this.nameAr,
    required this.unit,
    required this.quantity,
    required this.servingsLeft,
    required this.level,
    this.imageUrl,
  });

  factory MyMaterialDto.fromJson(Map<String, dynamic> json) =>
      _$MyMaterialDtoFromJson(json);

  final int itemId;
  final String nameAr;

  /// Admin-entered and in whatever language it was typed. Always bidi-isolated
  /// when rendered next to [quantity] (§2.4).
  final String unit;

  /// Sent as a JSON number; parsed as [num] so a decimal quantity does not
  /// truncate.
  final num quantity;

  final int servingsLeft;

  /// The colour band. Read [stockLevel] rather than comparing this by hand.
  final String level;

  /// Relative path, resolved against the API host — as on `CatalogueItemDto`.
  ///
  /// **Not yet returned by the API.** The field is nullable and the UI falls
  /// back to a category glyph, so images appear on their own once the backend
  /// change ships. See docs/backend-request-material-image.md.
  final String? imageUrl;

  StockLevel get stockLevel => StockLevel.fromWire(level);
}

/// The stock band behind the colour on a material row.
///
/// Colour is never the only signal: the quantity and a text label are always
/// shown alongside it (§2.5).
enum StockLevel {
  high('High'),
  medium('Medium'),
  low('Low'),
  empty('Empty');

  const StockLevel(this.wire);

  final String wire;

  /// Unknown bands fall back to [medium] — a neutral reading rather than a
  /// false alarm in either direction.
  static StockLevel fromWire(String value) => StockLevel.values.firstWhere(
    (l) => l.wire.toLowerCase() == value.toLowerCase(),
    orElse: () => StockLevel.medium,
  );
}

/// Mirrors `DeclareMaterialRequest` in ApiContracts.cs.
///
/// `POST /materials/declare` returns **`202 Accepted`, not `201`**. A
/// declaration creates nothing until an admin confirms receipt, so the
/// confirmation wording says "awaiting confirmation" and never "added" (§7.5).
@JsonSerializable(createFactory: false, includeIfNull: false)
class DeclareMaterialRequest {
  const DeclareMaterialRequest({
    required this.itemId,
    required this.quantity,
    this.note,
  });

  final int itemId;
  final num quantity;
  final String? note;

  Map<String, dynamic> toJson() => _$DeclareMaterialRequestToJson(this);
}
