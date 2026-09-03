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
    required this.allowedExtraItemIds,
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

  /// Which extras this drink permits, or **null when it permits every extra** —
  /// the default for a drink with no configured restriction. An empty list is
  /// different: it means no extras at all. **Never conflate the two.**
  ///
  /// Always null on sugars and extras, which have no extras of their own.
  ///
  /// Filtering on this is not cosmetic. An extra the drink does not permit is
  /// dropped **server-side while the order still succeeds**, so offering one
  /// produces a drink that arrives wrong rather than an error the user can act
  /// on.
  final List<int>? allowedExtraItemIds;

  /// Whether this drink permits [extraItemId].
  ///
  /// A null list means unrestricted, so everything is permitted; an empty list
  /// permits nothing.
  bool permitsExtra(int extraItemId) =>
      allowedExtraItemIds?.contains(extraItemId) ?? true;

  /// Whether the extras row should be shown for this drink at all.
  ///
  /// False only for the empty list — a drink configured to take no extras. A
  /// null list is unrestricted and shows every extra.
  bool get permitsAnyExtra => allowedExtraItemIds?.isNotEmpty ?? true;

  /// The item's name in [languageCode], falling back to Arabic.
  ///
  /// **The fallback is not optional.** `nameEn` is admin-entered and is empty
  /// for most items on the live server — قهوة تركية بالهيل, كركديه, نعناع and
  /// ينسون all have none. An English user must see the Arabic name rather than
  /// an empty tile, so Arabic is the floor for both locales.
  String localisedName(String languageCode) =>
      languageCode == 'ar' || nameEn.trim().isEmpty ? nameAr : nameEn;
}

/// Mirrors `VariantDto` in ApiContracts.cs.
@JsonSerializable(createToJson: false)
class VariantDto {
  const VariantDto({
    required this.variantId,
    required this.nameAr,
    required this.nameEn,
    required this.isDefault,
    this.ingredientItemIds = const [],
  });

  factory VariantDto.fromJson(Map<String, dynamic> json) =>
      _$VariantDtoFromJson(json);

  final int variantId;
  final String nameAr;
  final String nameEn;
  final bool isDefault;

  /// What this preparation **already pours** — the milk in a قهوة فرنساوي.
  ///
  /// Choosing one of these as an *extra* is a second portion and a second
  /// deduction: milk on a French coffee takes 22g for the recipe plus 30g for
  /// the extra, 52g in total. That is correct — two pours, two deductions —
  /// but it is the kind of correct that looks like a bug on the stock report if
  /// nobody says so first.
  ///
  /// **Annotate the extras picker with this; never filter it.** An ingredient
  /// is part of the recipe and cannot be declined, which is exactly what
  /// separates it from [CatalogueItemDto.allowedExtraItemIds]. And a double
  /// portion is a legitimate thing to order — warn, never block.
  ///
  /// Empty rather than null, unlike `allowedExtraItemIds`: there is no
  /// "unrestricted" case here. A preparation that pours nothing extra is
  /// completely described by `[]`. Defaulted so a server predating the field
  /// simply warns about nothing.
  final List<int> ingredientItemIds;

  /// Whether this preparation already pours [extraItemId], making it a second
  /// portion if also chosen as an extra.
  bool alreadyPours(int extraItemId) => ingredientItemIds.contains(extraItemId);

  /// As on [CatalogueItemDto.localisedName] — Arabic is the floor.
  String localisedName(String languageCode) =>
      languageCode == 'ar' || nameEn.trim().isEmpty ? nameAr : nameEn;
}

/// Mirrors `CatalogueResponse` in ApiContracts.cs.
///
/// Bundled deliberately: a phone on office wifi should not need four requests
/// to draw one screen.
///
/// **Carries no "usual order", and must not grow one back.** It used to: the
/// caller's last non-cancelled order, dressed up as a habit. It changed under
/// the user every time they ordered something for a visitor, and nobody chose
/// it. Favourites replaced it — the same one-tap repeat, stated rather than
/// guessed — and deliberately from a *separate* endpoint, since this response
/// is cached until resume while that list changes the moment the user saves
/// one — see `FavouriteDto` in `favourite_models.dart`.
@JsonSerializable(createToJson: false)
class CatalogueResponse {
  const CatalogueResponse({
    required this.drinks,
    required this.sugars,
    required this.extras,
    required this.locations,
    this.maxLines = 25,
    this.maxBuffetDrinks = 1,
  });

  factory CatalogueResponse.fromJson(Map<String, dynamic> json) =>
      _$CatalogueResponseFromJson(json);

  final List<CatalogueItemDto> drinks;
  final List<CatalogueItemDto> sugars;
  final List<CatalogueItemDto> extras;
  final List<LocationDto> locations;

  /// The most drinks one order may carry.
  ///
  /// Defaulted rather than required so a server that predates the field yields
  /// the limit it enforced anyway (`OrderService.MaxLines`) instead of failing
  /// to parse the whole catalogue.
  final int maxLines;

  /// How many drinks on this order may come from the buffet's own stock; the
  /// rest must come from the caller's own materials, or the order is rejected
  /// outright.
  ///
  /// **Counted on the source each line resolves to, not the one requested**:
  /// asking for a jar the caller does not actually own falls back to buffet
  /// stock and counts here. Defaulted for the same reason as [maxLines].
  final int maxBuffetDrinks;
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
