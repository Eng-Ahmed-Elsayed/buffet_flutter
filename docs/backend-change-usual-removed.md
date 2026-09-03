# Breaking change: `usual` removed from `/catalogue`

**Shipped:** 2026-09-02. **Kind:** removal — the only one so far, so read this before the next pull.
**Replaced by:** favourites, `GET`/`POST`/`DELETE /favourites` ([guide §7.6](flutter-app-guide.md)).

## What changed

`CatalogueResponse` no longer carries `usual`. The `UsualOrderDto` type is gone from the API, and so
is the web's matching "الطلب المعتاد" card.

```diff
  {
    "drinks": [...], "sugars": [...], "extras": [...], "locations": [...],
-   "usual": { "summary": "قهوة (بدون سكر)", "lines": [...] },
    "maxLines": 25,
    "maxBuffetDrinks": 1
  }
```

## Why

`usual` was the caller's most recent non-cancelled order, presented as a habit. It was not one. No
frequency, no weighting — order something unusual once for a visitor and it was your "usual" until
you ordered again. Nobody ever chose it.

Now that favourites exist, keeping both meant two one-tap repeats sitting next to each other, one
stated and one guessed, with the guessed one silently moving. That is worse than either alone: the
user cannot tell which is which.

So the guess went, and the stated one stays.

## You can deploy the backend first — nothing breaks

`catalogue_models.dart` already types the field as `UsualOrderDto? usual`, and an absent JSON key
deserialises to null rather than throwing. So on the current build the card simply stops appearing.
**No crash, no forced app update, no coordination needed.** Clean up whenever it suits you.

## What to delete

| File | What |
|---|---|
| `lib/features/order/widgets/usual_order_card.dart` | The whole widget |
| `lib/features/home/home_screen.dart` | The import, the `ref.watch(...).usual` read (~line 115) and the `if (usual != null)` block (~line 163) |
| `lib/features/order/composer_screen.dart` | The import, the prefill path (~lines 287–300) and the card at ~line 377 |
| `lib/features/order/composer_controller.dart` | `applyUsual` |
| `lib/data/models/catalogue_models.dart` | The `usual` field, then regenerate `.g.dart` |
| `lib/l10n/app_ar.arb`, `app_en.arb` | The card's strings |

## What to build instead

**1. The favourites strip**, where the card used to be — [guide §7.6](flutter-app-guide.md) has the
contract, the four traps and the cap. It is the same one-tap repeat, except the user decided what is
in it.

**2. "احفظ كطلب مفضل" on a past order**, in the order-history screen. This is the migration path for
anybody who liked the old button, and it needs **no backend work at all**:

```dart
// OrderSummaryDto.lines and SaveFavouriteRequest.lines are both OrderLineDto.
await api.saveFavourite(name: null, lines: pastOrder.lines);
```

Leave `name` null and the server names it after the drinks — including the preparation, which it was
previously dropping:

```
قهوة فرنساوي (2 سكر) + حليب
قهوة (بدون سكر)، شاي (1 سكر)
```

The difference from the old behaviour is the whole point: the user picks *which* past order was
actually a habit, instead of the server assuming the newest one was.

## Two smaller things in the same release

- **`DELETE /favourites/{id}` is now audited**, as `POST` already was. No contract change.
- **`/catalogue` got faster.** `usual` was the only consumer of an unbounded
  `GetOrdersAsync(RequesterUsername)` — every catalogue fetch was loading the employee's entire
  order history, lines and extras included, to use the newest one. That query is gone. If you were
  seeing the catalogue slow down for heavy users, that was why.

## Checklist

- [x] Backend deployed (safe on its own — see above)
- [x] Card and its usages deleted; `.g.dart` regenerated
- [x] Favourites strip in its place
- [x] "Save as favourite" on past orders
- [x] `grep -rn "usual" lib/` returns nothing — bar six doc comments that say
      *why* there is no usual, which is the point of keeping them

## What the client shipped (2026-09-02)

`flutter analyze` clean, `flutter test` 383 passing.

| Piece | Where |
|---|---|
| `FavouriteDto` / `SaveFavouriteRequest` / `FavouritesResponse` | `lib/data/models/favourite_models.dart` |
| `GET`/`POST`/`DELETE /favourites` | `lib/data/repositories/favourites_repository.dart` |
| `saveAsFavourite`, `favouriteName`, `fromFavouriteId`, `favouriteId` | `lib/data/models/order_models.dart` |
| The strip, on the hub **and** the composer | `lib/features/order/widgets/favourites_strip.dart` |
| The save toggle with its optional name | `_SaveFavouriteControl` in `composer_screen.dart` |
| "احفظ كطلب مفضل" on a past order | `lib/features/order/my_orders_screen.dart` |

Four decisions worth keeping:

1. **A tap seeds the composer; it does not place the order.** The user still
   sees and confirms the drink, and a favourite holding an item retired since it
   was saved shows up as a line they can look at rather than a rejection they
   cannot act on.
2. **The strip is on the composer as well as the hub.** Staff never see the hub
   — they push the composer from the queue — so a strip only there would take
   the one-tap repeat away from them entirely, exactly as the old card would
   have.
3. **`ComposerSeed` carries the whole `FavouriteDto`**, not an id. Favourites
   are a separate endpoint from the catalogue, so an id would mean refetching
   the list to look one up — a spinner between the tap and the drink.
4. **`maxFavourites` disables the save toggle, and only ever beside a banner
   saying why.** The cap is structural (the server refuses past it), which is
   the one kind of limit this app disables a control on — never a stock reading.
   `test/features/composer_screen_test.dart` pins both halves together.
