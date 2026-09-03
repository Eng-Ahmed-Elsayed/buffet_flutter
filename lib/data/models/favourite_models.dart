import 'package:json_annotation/json_annotation.dart';

import 'catalogue_models.dart';

part 'favourite_models.g.dart';

/// An order the employee saved to place again in one tap.
///
/// **This replaced the catalogue's "usual order"**, which was the last
/// non-cancelled order presented as a habit: it moved under the user every time
/// they ordered something for a visitor, and they never chose it. A favourite
/// changes only when they say so. That is the whole difference, and the reason
/// the guessed one was removed rather than kept beside this — two one-tap
/// repeats sitting together, one stated and one silently moving, is worse than
/// either alone.
@JsonSerializable(createToJson: false)
class FavouriteDto {
  const FavouriteDto({
    required this.favouriteId,
    required this.name,
    required this.createdAtUtc,
    required this.lastUsedAtUtc,
    required this.lines,
  });

  factory FavouriteDto.fromJson(Map<String, dynamic> json) =>
      _$FavouriteDtoFromJson(json);

  final int favouriteId;

  /// What the user called it, or a server-composed summary of the drinks when
  /// they did not name it — "قهوة فرنساوي (2 سكر) + حليب".
  ///
  /// **Never blank**, so a list never has to render a nameless row. Mixed
  /// script either way, so always bidi-isolated when rendered (§2.4).
  final String name;

  /// UTC. Convert for display; never render raw (§4).
  final DateTime createdAtUtc;

  /// When it was last ordered, or null until it has been ordered once.
  final DateTime? lastUsedAtUtc;

  /// The saved drinks, in the same shape `POST /orders` takes — replaying one
  /// is a straight repost of this array, with no translation or lookup.
  ///
  /// **Not revalidated on the way out.** An item retired since the favourite
  /// was saved still appears here, and the order replaying it is rejected at
  /// that point with a reason the user can act on. Do not pre-filter the list:
  /// a favourite that silently vanishes is worse than one that explains itself.
  final List<OrderLineDto> lines;

  /// Whether this favourite orders the same thing as [other].
  ///
  /// Compares only what is actually **ordered** — drink, preparation, sugar and
  /// extras, in order — and deliberately ignores the display name, the jar each
  /// part came from and the line note. Two saves of the same coffee are the
  /// same favourite whether or not the user named them differently, which is
  /// what makes "you already saved this" answerable at all.
  bool orders(List<OrderLineDto> other) {
    if (lines.length != other.length) return false;
    for (var i = 0; i < lines.length; i++) {
      if (!_sameLine(lines[i], other[i])) return false;
    }
    return true;
  }

  static bool _sameLine(OrderLineDto a, OrderLineDto b) =>
      a.drinkItemId == b.drinkItemId &&
      a.variantId == b.variantId &&
      a.sugarSpoons == b.sugarSpoons &&
      a.sugarItemId == b.sugarItemId &&
      _sameExtras(a.extraItemIds, b.extraItemIds);

  /// Order-insensitive: the composer builds extras from a Set, so two
  /// identical drinks can differ only in the order the user ticked them.
  static bool _sameExtras(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final left = a.toSet();
    return left.length == b.toSet().length && b.every(left.contains);
  }

  /// Whether every item this favourite names is still orderable.
  ///
  /// [availableItemIds] is what the catalogue currently carries. An admin can
  /// disable or delete a drink after a favourite was saved, and the server
  /// **deliberately does not filter these out** on the way back (§7.6): a
  /// favourite that silently vanished would leave the user with nothing to act
  /// on. So the client shows it and marks it instead.
  bool isAvailable(Set<int> availableItemIds) => lines.every(
    (line) =>
        availableItemIds.contains(line.drinkItemId) &&
        (line.sugarItemId == null ||
            availableItemIds.contains(line.sugarItemId)) &&
        line.extraItemIds.every(availableItemIds.contains),
  );
}

/// Mirrors `SaveFavouriteRequest` in ApiContracts.cs.
@JsonSerializable(createFactory: false, includeIfNull: false)
class SaveFavouriteRequest {
  const SaveFavouriteRequest({required this.lines, this.name});

  /// Optional. **Null means "name it after the drinks"** — the server composes
  /// one including the preparation, so the client never has to invent a label.
  final String? name;

  /// The same [OrderLineDto] the composer already builds, which is why saving a
  /// composed order — or reposting a past one — needs no second shape.
  final List<OrderLineDto> lines;

  Map<String, dynamic> toJson() => _$SaveFavouriteRequestToJson(this);
}

/// Mirrors `FavouritesResponse` in ApiContracts.cs.
@JsonSerializable(createToJson: false)
class FavouritesResponse {
  const FavouritesResponse({required this.favourites, this.maxFavourites = 20});

  factory FavouritesResponse.fromJson(Map<String, dynamic> json) =>
      _$FavouritesResponseFromJson(json);

  /// Newest first, as the server orders them.
  final List<FavouriteDto> favourites;

  /// How many one employee may keep.
  ///
  /// Published **so the save control can be disabled at the limit** rather than
  /// letting the user name a favourite and then be refused. This is a
  /// structural cap the server enforces, not a stock reading — the one kind of
  /// limit this app does disable a control on.
  ///
  /// Defaulted for the same reason as [CatalogueResponse.maxLines]: a server
  /// predating the field yields the limit it enforces anyway.
  final int maxFavourites;

  /// Whether the user has room to save another.
  bool get canSaveAnother => favourites.length < maxFavourites;
}
