import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/catalogue_models.dart';
import '../../data/models/order_models.dart';
import 'order_mode.dart';

/// One drink already added to the order, with the jar each part draws on.
///
/// Kept as a resolved snapshot rather than a set of ids: the buffet cap is
/// counted on the source a line *resolves* to, and that needs the item's own
/// stock reading at the moment it was added.
class ComposerLine {
  const ComposerLine({
    required this.drink,
    this.variantId,
    this.sugarItemId,
    this.sugarSpoons = 0,
    this.extraItemIds = const {},
    this.drinkFromOwn = false,
    this.sugarFromOwn = false,
    this.ownExtraItemIds = const {},
  });

  final CatalogueItemDto drink;
  final int? variantId;
  final int? sugarItemId;

  /// Zero is a valid, explicit choice — "no sugar" — not an empty field.
  final int sugarSpoons;

  final Set<int> extraItemIds;
  final bool drinkFromOwn;
  final bool sugarFromOwn;
  final Set<int> ownExtraItemIds;

  /// Whether this line will draw its drink from the **buffet's** stock.
  ///
  /// True when the user did not ask for their own jar — and **also** when they
  /// did but have nothing left in it. The server counts the cap on the source
  /// each line resolves to, not the one requested: claiming a jar you do not
  /// hold falls back to company stock and counts here. A client that counted
  /// the flag alone would let the user compose an order the server rejects.
  bool get resolvesToBuffet => !drinkFromOwn || drink.ownServingsLeft <= 0;

  /// Whether the user's own jar is empty for this line's drink.
  bool get ownStockIsShort => drinkFromOwn && drink.ownServingsLeft <= 0;

  OrderLineDto toDto() => OrderLineDto(
    drinkItemId: drink.itemId,
    drinkNameAr: drink.nameAr,
    sugarSpoons: sugarSpoons,
    variantId: variantId,
    sugarItemId: sugarItemId,
    extraItemIds: extraItemIds.toList(),
    lineNote: null,
    drinkFromOwn: drinkFromOwn,
    sugarFromOwn: sugarFromOwn,
    ownExtraItemIds: ownExtraItemIds.toList(),
  );
}

/// The composer's working state: the lines already added, plus the one being
/// composed now.
///
/// Deliberately **not** a wizard. The draft is the ordinary single-drink
/// composer, unchanged for the majority who order one coffee; adding a second
/// drink moves the draft into [lines] and clears the controls for the next one.
class ComposerState {
  const ComposerState({
    required this.idempotencyKey,
    this.lines = const [],
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
    this.onBehalfOfName,
    this.canOrderForGuests = false,
    this.mode = OrderMode.self,
    this.maxLines = 25,
    this.maxBuffetDrinks = 1,
  });

  /// Created when the composer opens and kept across retries — discarded only
  /// once an order is confirmed. A dropped response on office wifi otherwise
  /// becomes a second coffee (§7.2).
  final String idempotencyKey;

  /// Drinks already added. Empty for the ordinary one-drink order.
  final List<ComposerLine> lines;

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

  /// The guest this order is for, when the user holds the privilege.
  ///
  /// Sending it also lifts the buffet cap server-side — but only for a caller
  /// whose token actually carries `canOrderForGuests`.
  final String? onBehalfOfName;

  /// Whether the signed-in user holds the guest privilege, from the token.
  ///
  /// Held here so the cap rule is one expression in the model rather than half
  /// a rule in the model and half in a widget's `if`.
  final bool canOrderForGuests;

  /// Whether this session is composing for the user or for a guest.
  ///
  /// A property of how the composer was **opened**, not a control inside it.
  /// Defaults to [OrderMode.self] so every existing caller — the staff
  /// "order for myself" push above all — keeps its meaning without saying so.
  final OrderMode mode;

  /// Server-published caps, defaulted so a stale catalogue still enforces the
  /// limits the server applies anyway.
  final int maxLines;
  final int maxBuffetDrinks;

  /// Whether the selected drink is one the user owns any of.
  ///
  /// No longer gates a toggle — the source comes from which group's tile was
  /// tapped — but still says whether the own-jar tile existed for this drink.
  bool get canUseOwnMaterials => drink?.hasOwnStock ?? false;

  /// Whether to warn that the user's own jar is empty.
  ///
  /// This drives a **warning only**. It must never disable the order button:
  /// physical and recorded stock drift, and halting service is worse than a
  /// negative number an admin reconciles later.
  bool get ownStockIsShort =>
      drinkFromOwn && (drink?.ownServingsLeft ?? 0) <= 0;

  /// The preparation currently chosen, or null when the drink is made one way
  /// or none is selected.
  VariantDto? get selectedVariant =>
      drink?.variants.where((v) => v.variantId == variantId).firstOrNull;

  /// Whether [extraItemId] is **already poured by the chosen preparation**, so
  /// choosing it as an extra means a second portion and a second deduction.
  ///
  /// Follows the preparation, not the drink: milk is in a فرنساوي and not in a
  /// غامق, so the mark moves when the user switches between them.
  bool extraDoublesUp(int extraItemId) =>
      selectedVariant?.alreadyPours(extraItemId) ?? false;

  /// The chosen extras that the chosen preparation already pours.
  ///
  /// Drives the hint under the extras row. Empty when nothing doubles — which
  /// is the ordinary case.
  Set<int> get doubledExtraItemIds => {
    for (final id in extraItemIds)
      if (extraDoublesUp(id)) id,
  };

  /// The draft as a line, or null when no drink is selected.
  ComposerLine? get draftLine => drink == null
      ? null
      : ComposerLine(
          drink: drink!,
          variantId: variantId,
          sugarItemId: sugarItemId,
          sugarSpoons: sugarSpoons,
          extraItemIds: extraItemIds,
          drinkFromOwn: drinkFromOwn,
          sugarFromOwn: sugarFromOwn,
          ownExtraItemIds: ownExtraItemIds,
        );

  /// Every line the order would carry: those added, plus the draft if it has a
  /// drink. A drink left in the draft is part of the order — abandoning it
  /// silently on submit would drop a drink the user chose.
  ///
  /// **Never truncated.** Silently dropping a line the user can still see on
  /// screen is worse than the rejection it avoids — they would get a short
  /// order with no idea why. The cap is instead enforced where a line is
  /// *created*: [ComposerController.addLine] refuses past it, and the drink
  /// grid stops selecting a new draft once the list is full, so this can only
  /// exceed [maxLines] if those two are wrong.
  List<ComposerLine> get allLines => [
    ...lines,
    if (draftLine case final ComposerLine draft) draft,
  ];

  /// Whether the order carries more lines than the server will accept.
  ///
  /// A safety net rather than an expected state — it stays false as long as the
  /// two guards above hold. Surfaced so the UI can say so rather than letting
  /// the user meet a `400` they cannot interpret.
  bool get exceedsLineCap => allLines.length > maxLines;

  /// Whether a guest order is still missing the one thing it needs.
  ///
  /// Only ever true in [OrderMode.guest]: a self order has no guest to name.
  bool get guestNameMissing =>
      mode == OrderMode.guest && (onBehalfOfName ?? '').trim().isEmpty;

  /// Whether the order can be sent.
  ///
  /// Gated on the guest name in guest mode — which is a **validation** gate on
  /// a required field, the same kind as [canAddAnotherLine], and categorically
  /// not a stock reading. The screen pairs it with a visible error message, so
  /// the disabled button is never a dead end.
  bool get canPlaceOrder => allLines.isNotEmpty && !guestNameMissing;

  /// How many drinks on this order will draw on buffet stock.
  int get buffetDrinkCount => allLines.where((l) => l.resolvesToBuffet).length;

  /// Whether the guest privilege lifts the cap for this order.
  ///
  /// **Both halves are required**, matching the server exactly. The privilege
  /// alone must not lift the cap on an ordinary order, or a privileged employee
  /// could quietly take ten cups for themselves; and the name alone must not
  /// either, since it comes from a field the client controls.
  bool get capIsLifted =>
      canOrderForGuests && (onBehalfOfName ?? '').trim().isNotEmpty;

  /// Whether the order has room for another drink.
  ///
  /// Counted on [lines] rather than [allLines]: committing the draft *moves*
  /// it into the list rather than adding to the total, so measuring the draft
  /// here would refuse the last drink the order can legally carry.
  ///
  /// This is a **structural** limit, not a stock reading: the server rejects
  /// the order outright past it, so blocking here stops the user composing
  /// something that cannot be placed. Distinct from a shortage, which only
  /// ever warns.
  bool get canAddAnotherLine => lines.length < maxLines;

  /// Whether this order already draws more drinks from buffet stock than the
  /// server will accept.
  ///
  /// Reported so the UI can explain *at the point of adding* that the rest must
  /// come from the user's own materials — not by catching a `400` after the
  /// whole order has been composed.
  ///
  /// **This never disables the order button.** A line counts against the cap
  /// when `ownServingsLeft <= 0`, which is a stock reading, and a control
  /// switched off on a stock reading is the one thing the domain rules forbid
  /// outright — balances drift, and the user fixes this by switching a drink to
  /// their own jar or removing one. What it *does* gate is
  /// [ComposerController.addLine], so the violation cannot grow while it
  /// stands.
  bool get exceedsBuffetCap =>
      !capIsLifted && buffetDrinkCount > maxBuffetDrinks;

  /// Whether committing the draft would push the order past the buffet cap.
  ///
  /// Distinct from [exceedsBuffetCap], which describes the order as it stands.
  bool get draftWouldExceedBuffetCap {
    if (capIsLifted || draftLine == null) return false;
    return lines.where((l) => l.resolvesToBuffet).length +
            (draftLine!.resolvesToBuffet ? 1 : 0) >
        maxBuffetDrinks;
  }

  ComposerState copyWith({
    String? idempotencyKey,
    List<ComposerLine>? lines,
    CatalogueItemDto? Function()? drink,
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
    String? Function()? onBehalfOfName,
    bool? canOrderForGuests,
    OrderMode? mode,
    int? maxLines,
    int? maxBuffetDrinks,
  }) => ComposerState(
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    lines: lines ?? this.lines,
    drink: drink != null ? drink() : this.drink,
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
    onBehalfOfName: onBehalfOfName != null
        ? onBehalfOfName()
        : this.onBehalfOfName,
    canOrderForGuests: canOrderForGuests ?? this.canOrderForGuests,
    mode: mode ?? this.mode,
    maxLines: maxLines ?? this.maxLines,
    maxBuffetDrinks: maxBuffetDrinks ?? this.maxBuffetDrinks,
  );

  /// Builds the wire request. Each line carries which jar its components come
  /// from, per `OrderLineDto`.
  PlaceOrderApiRequest toRequest() => PlaceOrderApiRequest(
    lines: [for (final line in allLines) line.toDto()],
    notes: notes,
    locationId: locationId,
    locationText: locationText,
    onBehalfOfName: onBehalfOfName,
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

  /// Adopts the caps the server published with the catalogue, so the limit is
  /// not duplicated as a magic number in the client.
  /// A refetched catalogue can publish a *lower* cap than the one in force when
  /// the user started composing — a language switch mid-order is enough to
  /// trigger it. The new cap is adopted for what may be added next, but never
  /// applied retroactively to lines the user has already put in the order:
  /// removing a drink they can see, without being asked, is not the client's
  /// call. The order is left to the server, which owns the rule.
  /// Records whether the signed-in user holds the guest privilege.
  void setCanOrderForGuests(bool value) {
    if (state.canOrderForGuests == value) return;
    state = value
        ? state.copyWith(canOrderForGuests: true)
        // A privilege that has gone away cannot leave a guest name behind: the
        // server would reject it, and until then it would wrongly lift the cap.
        : state.copyWith(canOrderForGuests: false, onBehalfOfName: () => null);
  }

  /// Records whether this session composes for the user or for a guest.
  ///
  /// Called by the screen from the seed it was opened with, never by a user
  /// control — the mode is a property of how the composer was **opened**.
  ///
  /// **Never mints a new idempotency key.** This is the same composer session
  /// the key was created for, and a key that changed when the mode was applied
  /// would turn a retry into a second drink (§7.2).
  ///
  /// Leaving guest mode drops the guest name: a self order that still carried
  /// one would wrongly lift the buffet cap, and the server would reject it.
  void setMode(OrderMode mode) {
    if (state.mode == mode) return;
    state = mode == OrderMode.guest
        ? state.copyWith(mode: mode)
        : state.copyWith(mode: mode, onBehalfOfName: () => null);
  }

  void applyLimits({required int maxLines, required int maxBuffetDrinks}) {
    final effective = maxLines < state.lines.length
        ? state.lines.length
        : maxLines;

    if (state.maxLines == effective &&
        state.maxBuffetDrinks == maxBuffetDrinks) {
      return;
    }
    state = state.copyWith(
      maxLines: effective,
      maxBuffetDrinks: maxBuffetDrinks,
    );
  }

  /// Selects a drink, and with it **which jar it comes from**.
  ///
  /// [fromOwn] is not a separate question the user answers afterwards — it is
  /// carried by the tile they tapped. A drink they own appears under both
  /// headings, once per jar, so the choice is made before the drink is picked
  /// rather than as a toggle underneath it. A second control asking the same
  /// thing would quietly contradict the tile above it.
  void selectDrink(CatalogueItemDto drink, {bool fromOwn = false}) {
    // At the cap with no draft, a new selection would push the order one line
    // over. Refused here rather than dropped at submit: a tile that looks
    // selected but is missing from the order is a lie the user cannot see.
    // Replacing an existing draft is always fine — the count does not change.
    if (state.drink == null && !state.canAddAnotherLine) return;

    final defaultVariant = drink.variants.where((v) => v.isDefault).firstOrNull;

    state = state.copyWith(
      drink: () => drink,
      variantId: () => defaultVariant?.variantId,
      // Never inherited from the previous drink: it comes from the tile, and
      // a drink the user does not own has no own-jar tile to come from.
      drinkFromOwn: fromOwn && drink.hasOwnStock,
      // An extra the new drink does not permit is dropped server-side while
      // the order still succeeds, so carrying one over produces a drink that
      // arrives wrong rather than an error the user can act on (§6).
      extraItemIds: state.extraItemIds.where(drink.permitsExtra).toSet(),
      ownExtraItemIds: state.ownExtraItemIds.where(drink.permitsExtra).toSet(),
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

  /// Changes the jar for the drink already in the draft.
  ///
  /// The composer sets this through [selectDrink] instead — the tile carries
  /// the answer. Kept for [applyUsual], which replays the source a past order
  /// recorded, and refuses a jar the user does not own so the flag can never
  /// claim stock that is not there.
  void setDrinkFromOwn(bool value) => state = state.copyWith(
    drinkFromOwn: value && (state.drink?.hasOwnStock ?? false),
  );

  void setSugarFromOwn(bool value) =>
      state = state.copyWith(sugarFromOwn: value);

  void setLocation({int? locationId, String? locationText}) => state = state
      .copyWith(locationId: () => locationId, locationText: () => locationText);

  void setNotes(String? notes) => state = state.copyWith(notes: () => notes);

  /// Names the guest this order is for. Only ever called when the signed-in
  /// user holds `canOrderForGuests` — the server reads that from the token and
  /// rejects a guest name from anyone else.
  void setOnBehalfOfName(String? name) => state = state.copyWith(
    onBehalfOfName: () =>
        (name == null || name.trim().isEmpty) ? null : name.trim(),
  );

  /// Commits the draft to [ComposerState.lines] and clears the controls for the
  /// next drink.
  ///
  /// A no-op when there is no drink to add, or when [ComposerState.lines] is
  /// already at [ComposerState.maxLines] — the server rejects past it, so there
  /// is nothing to be gained by letting the user compose one more.
  void addLine() {
    final draft = state.draftLine;
    if (draft == null || !state.canAddAnotherLine) return;
    // Refused while it would break the cap. The user is told why by the banner
    // and fixes it by switching this drink to their own jar — which is exactly
    // the choice the rule exists to force.
    if (state.draftWouldExceedBuffetCap) return;

    state = ComposerState(
      idempotencyKey: state.idempotencyKey,
      lines: [...state.lines, draft],
      // Everything scoped to the whole order survives; only the per-drink
      // controls reset.
      locationId: state.locationId,
      locationText: state.locationText,
      notes: state.notes,
      onBehalfOfName: state.onBehalfOfName,
      canOrderForGuests: state.canOrderForGuests,
      // Carried deliberately. This constructor rebuilds field by field, so a
      // mode left out here would drop the user back into self mode — and null
      // the guest name with it — the moment they added a second drink.
      mode: state.mode,
      maxLines: state.maxLines,
      maxBuffetDrinks: state.maxBuffetDrinks,
    );
  }

  /// Removes an added line. Out-of-range indices are ignored rather than
  /// throwing — a stale tap from a rebuilt list must not crash the composer.
  void removeLine(int index) {
    if (index < 0 || index >= state.lines.length) return;
    state = state.copyWith(lines: [...state.lines]..removeAt(index));
  }

  /// Fills the composer from the usual order — the single highest-value
  /// feature in the app, and one tap from the top of the screen.
  ///
  /// Fills the **draft**, replacing whatever was being composed, and leaves any
  /// added lines alone: repeating the usual on top of a part-built order should
  /// add to it, not silently discard it.
  void applyUsual(UsualOrderDto usual, List<CatalogueItemDto> drinks) {
    final line = usual.lines.firstOrNull;
    if (line == null) return;

    final drink = drinks.where((d) => d.itemId == line.drinkItemId).firstOrNull;
    if (drink == null) return;

    state = state.copyWith(
      drink: () => drink,
      variantId: () => line.variantId,
      sugarItemId: () => line.sugarItemId,
      sugarSpoons: line.sugarSpoons,
      // The usual is the user's own past order, but the drink's permitted
      // extras may have been narrowed by an admin since it was placed.
      extraItemIds: line.extraItemIds.where(drink.permitsExtra).toSet(),
      drinkFromOwn: line.drinkFromOwn,
      sugarFromOwn: line.sugarFromOwn,
      ownExtraItemIds: line.ownExtraItemIds.where(drink.permitsExtra).toSet(),
    );
  }

  /// Called only once an order is **confirmed**, never on a failed attempt —
  /// a retry must reuse the same key.
  void resetAfterConfirmedOrder() => state = ComposerState(
    idempotencyKey: _newKey(),
    canOrderForGuests: state.canOrderForGuests,
    // The mode survives — it is still the same screen, opened the same way.
    // The guest name does NOT: the next guest is a different guest.
    mode: state.mode,
    maxLines: state.maxLines,
    maxBuffetDrinks: state.maxBuffetDrinks,
  );
}

final composerControllerProvider =
    StateNotifierProvider.autoDispose<ComposerController, ComposerState>(
      (ref) => ComposerController(),
    );
