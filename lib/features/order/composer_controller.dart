import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/catalogue_models.dart';
import '../../data/models/order_models.dart';

/// The composer's working state for one drink.
class ComposerState {
  const ComposerState({
    required this.idempotencyKey,
    this.drink,
    this.variantId,
    this.sugarItemId,
    this.sugarSpoons = 0,
    this.extraItemIds = const {},
    this.drinkFromOwn = false,
    this.sugarFromOwn = false,
    this.ownExtraItemIds = const {},
    this.locationId,
    this.locationText,
    this.notes,
  });

  /// Created when the composer opens and kept across retries — discarded only
  /// once an order is confirmed. A dropped response on office wifi otherwise
  /// becomes a second coffee (§7.2).
  final String idempotencyKey;

  final CatalogueItemDto? drink;
  final int? variantId;
  final int? sugarItemId;

  /// Zero is a valid, explicit choice — "no sugar" — not an empty field.
  final int sugarSpoons;

  final Set<int> extraItemIds;
  final bool drinkFromOwn;
  final bool sugarFromOwn;
  final Set<int> ownExtraItemIds;
  final int? locationId;
  final String? locationText;
  final String? notes;

  /// The "from my materials" toggle appears **only once a drink the user owns
  /// is selected** — showing it always is noise for the majority who own
  /// nothing (§7.1).
  bool get canUseOwnMaterials => drink?.hasOwnStock ?? false;

  /// Whether to warn that the user's own jar is empty.
  ///
  /// This drives a **warning only**. It must never disable the order button:
  /// physical and recorded stock drift, and halting service is worse than a
  /// negative number an admin reconciles later.
  bool get ownStockIsShort =>
      drinkFromOwn && (drink?.ownServingsLeft ?? 0) <= 0;

  bool get canPlaceOrder => drink != null;

  ComposerState copyWith({
    String? idempotencyKey,
    CatalogueItemDto? drink,
    int? Function()? variantId,
    int? Function()? sugarItemId,
    int? sugarSpoons,
    Set<int>? extraItemIds,
    bool? drinkFromOwn,
    bool? sugarFromOwn,
    Set<int>? ownExtraItemIds,
    int? Function()? locationId,
    String? Function()? locationText,
    String? Function()? notes,
  }) => ComposerState(
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    drink: drink ?? this.drink,
    variantId: variantId != null ? variantId() : this.variantId,
    sugarItemId: sugarItemId != null ? sugarItemId() : this.sugarItemId,
    sugarSpoons: sugarSpoons ?? this.sugarSpoons,
    extraItemIds: extraItemIds ?? this.extraItemIds,
    drinkFromOwn: drinkFromOwn ?? this.drinkFromOwn,
    sugarFromOwn: sugarFromOwn ?? this.sugarFromOwn,
    ownExtraItemIds: ownExtraItemIds ?? this.ownExtraItemIds,
    locationId: locationId != null ? locationId() : this.locationId,
    locationText: locationText != null ? locationText() : this.locationText,
    notes: notes != null ? notes() : this.notes,
  );

  /// Builds the wire request. The line carries which jar each component comes
  /// from, per `OrderLineDto`.
  PlaceOrderApiRequest toRequest() => PlaceOrderApiRequest(
    lines: [
      OrderLineDto(
        drinkItemId: drink!.itemId,
        drinkNameAr: drink!.nameAr,
        sugarSpoons: sugarSpoons,
        variantId: variantId,
        sugarItemId: sugarItemId,
        extraItemIds: extraItemIds.toList(),
        lineNote: null,
        drinkFromOwn: drinkFromOwn,
        sugarFromOwn: sugarFromOwn,
        ownExtraItemIds: ownExtraItemIds.toList(),
      ),
    ],
    notes: notes,
    locationId: locationId,
    locationText: locationText,
    idempotencyKey: idempotencyKey,
  );
}

class ComposerController extends StateNotifier<ComposerState> {
  ComposerController() : super(ComposerState(idempotencyKey: _newKey()));

  /// A UUID v4, generated locally. `Random.secure()` because a predictable key
  /// from another client could collide with this order.
  static String _newKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // Set the version (4) and variant bits per RFC 4122.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  void selectDrink(CatalogueItemDto drink) {
    final defaultVariant = drink.variants.where((v) => v.isDefault).firstOrNull;

    state = state.copyWith(
      drink: drink,
      variantId: () => defaultVariant?.variantId,
      // Selecting a different drink cannot carry the previous drink's "from my
      // jar" answer — the new one may not be owned at all.
      drinkFromOwn: false,
    );
  }

  void selectVariant(int? variantId) =>
      state = state.copyWith(variantId: () => variantId);

  void selectSugar(int? sugarItemId) =>
      state = state.copyWith(sugarItemId: () => sugarItemId);

  /// Zero is a floor, not a special case: "no sugar" is a choice the user makes
  /// and the server distinguishes it from unspecified.
  void setSugarSpoons(int spoons) =>
      state = state.copyWith(sugarSpoons: spoons.clamp(0, 10));

  void toggleExtra(int itemId) {
    final next = Set<int>.from(state.extraItemIds);
    if (!next.remove(itemId)) next.add(itemId);

    // An extra that is no longer selected cannot still be sourced from the
    // user's own jar.
    final ownNext = Set<int>.from(state.ownExtraItemIds)
      ..removeWhere((id) => !next.contains(id));

    state = state.copyWith(extraItemIds: next, ownExtraItemIds: ownNext);
  }

  void setDrinkFromOwn(bool value) =>
      state = state.copyWith(drinkFromOwn: value);

  void setSugarFromOwn(bool value) =>
      state = state.copyWith(sugarFromOwn: value);

  void setLocation({int? locationId, String? locationText}) => state = state
      .copyWith(locationId: () => locationId, locationText: () => locationText);

  void setNotes(String? notes) => state = state.copyWith(notes: () => notes);

  /// Fills the composer from the usual order — the single highest-value
  /// feature in the app, and one tap from the top of the screen.
  void applyUsual(UsualOrderDto usual, List<CatalogueItemDto> drinks) {
    final line = usual.lines.firstOrNull;
    if (line == null) return;

    final drink = drinks.where((d) => d.itemId == line.drinkItemId).firstOrNull;
    if (drink == null) return;

    state = state.copyWith(
      drink: drink,
      variantId: () => line.variantId,
      sugarItemId: () => line.sugarItemId,
      sugarSpoons: line.sugarSpoons,
      extraItemIds: line.extraItemIds.toSet(),
      drinkFromOwn: line.drinkFromOwn,
      sugarFromOwn: line.sugarFromOwn,
      ownExtraItemIds: line.ownExtraItemIds.toSet(),
    );
  }

  /// Called only once an order is **confirmed**, never on a failed attempt —
  /// a retry must reuse the same key.
  void resetAfterConfirmedOrder() =>
      state = ComposerState(idempotencyKey: _newKey());
}

final composerControllerProvider =
    StateNotifierProvider.autoDispose<ComposerController, ComposerState>(
      (ref) => ComposerController(),
    );
