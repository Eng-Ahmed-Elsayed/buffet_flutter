import '../../data/models/favourite_models.dart';

/// Who an order is being composed for.
///
/// Chosen **before** the composer opens, by which action the user tapped on the
/// home screen — never by a control inside the composer. The two cases ask for
/// different things and the server enforces different rules on them, so making
/// the user discover the difference by typing into an optional field was the
/// wrong shape: ordering for a visitor and ordering for yourself are not the
/// same task with one extra field, they are two tasks.
enum OrderMode {
  /// The ordinary case. No guest field at all, and the buffet cap applies.
  self,

  /// For a visitor. Names the guest as `onBehalfOfName`, which also **lifts the
  /// buffet cap** — but only for a caller whose token carries the privilege
  /// (§7.1.2). Both halves are required, server-side and here.
  guest,
}

/// How a composer session was opened.
///
/// Travels as `GoRouterState.extra` rather than as a path or query segment, and
/// deliberately so: a deep link carrying `mode=guest` could be opened by a user
/// whose token lacks `canOrderForGuests`, which produces exactly the
/// unexplained rejection that gating the field on the privilege exists to
/// prevent. `extra` cannot be typed into a URL bar, which is the property
/// wanted here. Push deep links only ever target `/order/{id}`, never `/order`,
/// so nothing is lost by it being unserialisable.
class ComposerSeed {
  const ComposerSeed({this.mode = OrderMode.self, this.favourite});

  final OrderMode mode;

  /// The favourite to fill the composer from on open, or null for an empty one.
  ///
  /// Carried **whole** rather than as an id or a flag, unlike the "usual order"
  /// this replaced: that came from the catalogue the composer already fetched,
  /// so a flag was enough. Favourites are a separate endpoint, and making the
  /// composer refetch the list just to look one up would put a spinner between
  /// the tap and the drink — the delay the one-tap repeat exists to avoid.
  ///
  /// Seeds the composer rather than placing outright: the user still sees and
  /// confirms what they are ordering, and a favourite holding an item retired
  /// since it was saved shows up as a line they can see rather than a rejection
  /// they cannot act on (§7.6).
  final FavouriteDto? favourite;
}
