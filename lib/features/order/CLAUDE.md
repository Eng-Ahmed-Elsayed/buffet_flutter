# Ordering: composer, orders, favourites

Loaded when working in this directory. Moved out of the root CLAUDE.md *Current state*;
covers the composer, order tracking, favourites and guest mode. The root file's Standing rules and Domain rules still apply here.

**The guest privilege is read from the catalogue** (`CatalogueResponse.canOrderForGuests`, fresh
from the account on every fetch) through `guestPrivilegeProvider`, which falls back to the sign-in
value only when the catalogue has none. Never read `canOrderForGuestsProvider` directly for a
screen: it is the 30-day token claim, and the server checks the stored account instead. See
[docs/backend-request-guest-flag-freshness.md](docs/backend-request-guest-flag-freshness.md)
(done in the backend 2026-09-28, not yet deployed). Home refetches the catalogue on resume for
this, since it stays mounted beneath every tab (`home_screen_test.dart`).

**Review asks pickup or delivery** (§7.8, `fulfilment`), except of staff, whose own order is made
and handed over at once. Nothing is preselected until a first choice, which is then remembered on
the device (`pref_fulfilment`, cleared with the account) and carried through `addLine` and a
confirmed order like `mode`. **Never a disabled button**: Place order with neither chosen says so
under the choice, and delivery with no location puts the error on the location field, which the
server would otherwise refuse with a `400`. `composer_journeys_test.dart`. **The location is
remembered the same way** (`pref_location_id`, written on a confirmed order, cleared with the
account) and restored once, only while nothing is chosen and only if it is still in
`catalogue.locations`; a user who then picks "no location" keeps that.

**A failed catalogue refresh never replaces the composer.** Home refetches the catalogue on every
resume, and the composer watches the same provider; `skipError: true` keeps the step (Review and
Place order included) on screen, with a "Couldn't refresh" notice and Retry in the step's header.
Home does the same above its menu. `composer_journeys_test.dart`, `home_screen_test.dart`.

**The composer is one route with three steps**, `ComposerStep` Choose a drink → Drink Details →
Review ([docs/figma-redesign.md](docs/figma-redesign.md), *Ordering*). It is not three routes:
the draft, the guest name and the idempotency key belong to one order and one screen owns them.
Rules a future edit must not undo:

- **Back unwinds the steps before it leaves** (`PopScope` plus `_steps`). "Add another drink"
  stacks Choose **on top of** Review, because clearing the stack made back discard every line
  already added. Continue returns to the existing Review rather than stacking a second one.
  Removing the draft drops its Drink Details step, so back never lands on a blank step.
- **Quantity is identical lines** (`draftQuantity`), capped by `maxDraftQuantity` from structural
  limits only: lines count by their *requested* jar, never a stock reading. An own jar that reads
  empty keeps its stepper; the cap is enforced when adding, with the reason stated.
- **Place order is disabled only for an empty order, and Review then says so** with a way back.
  A missing guest name takes the user back to the field instead.
- **Once the order has used its buffet drink, "Add another drink" offers only the user's own
  materials** (`buffetAllowanceUsed`, `DrinkMenu.ownOnly`, counted by *requested* jar, never a
  stock reading). Choose a drink then lists «من موادي» alone, with a banner saying why. A user who
  owns nothing gets no button, and Review says why instead. A guest order, whose name lifts the
  cap, and a first drink from the user's own jar keep the buffet on offer. `composer_screen_test.dart`.
- **Home and Choose a drink render the same `DrinkMenu`**, so the two can never list drinks
  differently. It must sit in a non-lazy scroll view (see Home).
- **A favourite is replayed whole**: every line, the earlier ones added and the last as the draft,
  within the line cap **and the buffet cap**. What does not fit, or has been retired, is named in a
  notice; it is never dropped silently. Replaying only the first line placed a different order from
  the one saved.
- **`/favourites-list` returns its pick to the composer that opened it** (`returnsPick`). It
  used to push a second composer, and two composers share one provider: a guest name was wiped, the
  idempotency key was shared, and a staff member's served confirmation was lost.
- **Leaving asks before discarding an order** (Review with drinks, lines already added, or a failed
  placement), and never mid-placement. A single drink opened from Home backs out freely.
- **A failed placement stays on Review** until the next attempt, scrolled into view with the
  keyboard lowered, never a SnackBar over the retry button. Only an uncertain failure (no
  response, or a 5xx) says the order may have gone through; a 4xx is a refusal with the server's
  reason. The notices live inside the step's scroll view, via its `header` slot, so they never
  squeeze the step at 320dp. `composer_journeys_test.dart` pins all of this.

**The Orders tab has the design's two tabs**: In progress (Ready first, then Pending and
InProgress) and Earlier (Completed and Cancelled). The tracking screen shows a vertical four-step
timeline (Sent → Being prepared → Ready → Received) and carries the order's times, so the summary
card does not repeat them. Rules a future edit must not undo:

- **Ready wording follows the order's mode** (§7.8): collect it from the kitchen for a pickup,
  "will reach you shortly" for a delivery (Ready means made, not on its way), on the status screen
  and the local alert alike. **An order with no mode stays neutral** («جاهز لك»), which is every
  order on a server that predates the field. **"I picked it up"** (green, `ok`) shows only on the
  employee's own Ready *pickup*, posts `/orders/{id}/collected`, and needs no dialog: a repeat is a
  harmless `204`. `order_tracking_test.dart`.
- **An order row names its drinks from the catalogue in the reader's language**, exactly as the
  status screen does, falling back to the stored `drinkNameAr`. `OrderSummaryDto` carries Arabic
  names only, and a row saying «قهوة» that opens onto "Coffee" names one drink two ways.
  `order_tracking_test.dart` pins it in English.
- **A drink is pictured wherever it is named** (as in the design): menu rows, Drink Details and
  Review from the catalogue item, and the order rows, the tracking lines and Home's outstanding
  card through `DrinkPhoto`, which looks the id up in the catalogue (a neutral frame while it
  loads, the glyph for a retired drink). Favourite cards take the drink from their caller and read
  no provider; in the strip the photo sits above the name. `drink_photo_test.dart`. The photos are
  admin uploads, so how good they look is content, not code.
- **Times say the day only when it is not today** (`Formatters.moment`), in the list and on the
  timeline alike. "Being prepared" carries `startedAtUtc`, and a drink served straight from
  Pending passes that step without a time; it is never backfilled. A finished order's last step is announced as done, never as the current step.

**An extra's violet follows the jar it is drawn from, not ownership.** Ticking an extra the user
owns, with servings left, puts it in `ownExtraItemIds`. A source row under the extras (the same
`_SourceChip` as the drink's) switches it to the buffet. The chip used to be violet whenever the
user owned some, while the order sent it as buffet stock. **There is no sugar jar toggle**,
deliberately, and `sugarFromOwn` is never set by Drink Details. **Which sugar is chosen, though:**
the server resolves a sugar only when exactly one is active (`OrderService.ResolveSugar`); with two
or more and no `sugarItemId` it silently zeroes the spoons. So the first spoon picks the first
sugar, chips offer the others when there is more than one, and back to zero clears it. **A chip
shows as chosen only when it is the `sugarItemId` being sent**, never a fallback: a replayed
favourite with spoons and no sugar shows none chosen. Open: a *private* sugar in the list is drawn
from the owner's jar server-side but is not painted violet. `composer_own_extras_test.dart`,
`sugar_choice_test.dart`.

**The catalogue's `usual` is gone and must not come back.** It was the caller's last
non-cancelled order presented as a habit — no frequency, no weighting — and it moved under the user
every time they ordered for a visitor. **Favourites** (`GET`/`POST`/`DELETE /favourites`, §7.6)
replaced it: the same one-tap repeat, stated rather than guessed. The whole point of the removal was
that two shortcuts side by side, one silently moving, is worse than either alone, so **never add a
"last order" card next to the strip**. The rationale and the shipped inventory are in
[docs/backend-change-usual-removed.md](docs/backend-change-usual-removed.md). Four rules from it:

- **A tap seeds the composer; it never places the order.** The user confirms what they are
  ordering, and a favourite holding a since-retired item shows as a visible line rather than an
  opaque rejection. Favourites are deliberately **not** pre-filtered server-side — let the order be
  the thing that fails.
- **The strip lives on the composer's Choose-a-drink step as well as Home**, for the same reason
  `prepareLandingPrompts` does: staff never see Home, they push the composer from the queue.
- **`ComposerSeed` carries the whole `FavouriteDto`**, not an id — favourites are a separate
  endpoint from the catalogue, so an id would mean a refetch between the tap and the drink. And
  `saveAsFavourite` / `favouriteName` / `fromFavouriteId` must stay in **both** `ComposerState`
  constructor calls, exactly like `mode`.
- **`maxFavourites` is the one cap that may disable a control**, because it is structural — the
  server refuses past it — and only ever with the banner beside it saying so. Never a stock reading.
- **The strip shows four *most recently used*, then defers to the full list** — and truncates
  **only when a "show all" destination exists**, since hiding a favourite behind a link that is not
  there loses it as silently as filtering a retired one out. On Home that destination is the
  **Favourites tab**, so the strip passes `restReachableElsewhere` and draws no link. On the
  composer it links to `/favourites-list`. Sorted by `lastUsedAtUtc`, which is what that
  field is published for.
- **The strip's tiles are measured two-per-row, never a fixed `maxWidth`.** A 220dp cap put one card
  per row on a 320dp phone, and four favourites pushed "New order" — then the primary action of the
  whole app — out of the built viewport entirely. The responsive suite did **not** catch it, because
  it checks for overflow and nothing overflowed. `home_screen_test.dart` now asserts that the
  **search field and the owed order** (the first ways into ordering, placed above the strip) are
  reachable without scrolling **above the tab bar**, with Home inside the real shell. With no
  favourites, the first menu row must be in reach too.
- **A favourite whose item an admin retired is shown and marked, never hidden or disabled.** The
  server does not filter these (§7.6), and it is right not to: one that vanished silently would
  leave the user nothing to act on and no way to delete what they cannot see. It still taps — the
  composer is where the missing drink becomes a visible line. `favourites_strip_test.dart` pins it.
- **A favourite is a heart everywhere**, as the design's tab bar draws it. A star beside a heart
  read as two different things.
- **An order already saved says so; it does not offer to save again.** `FavouriteDto.orders()`
  compares only what is *ordered* — drink, preparation, sugar, extras — ignoring the name and the
  jar, so two saves of the same coffee are one favourite. The action is **replaced by a statement**,
  never greyed out.

**Guest ordering is a composer *mode*, not a field.** `ComposerSeed` travels as `GoRouterState.extra`
(never a query parameter — a URL must not be able to assert a privilege the token may not carry).
Self mode shows no guest field at all; guest mode asks for the name first and requires it. Two rules
a future edit must not undo:

- **`setMode` never mints a new idempotency key**, and `addLine()` / `resetAfterConfirmedOrder()`
  rebuild `ComposerState` field by field — so `mode` must stay in both constructor calls or a second
  drink silently drops the user back into a self order. Covered by `test/features/composer_mode_test.dart`.
- **The guest name gates the order button but never disables it.** The handler reveals the error on
  the field instead; a disabled control with no stated reason is the dead end this codebase avoids.
