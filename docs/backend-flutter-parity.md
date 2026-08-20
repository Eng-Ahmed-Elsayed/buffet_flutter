# Backend ↔ Flutter parity: what each side is missing

**Written:** 2026-08-20. **Backend:** `buffet_app` (ASP.NET Core 10). **Client:** `buffet_flutter`.

**Status: the backend side is done and merged into the guide.** Everything marked ✅ below is
implemented, tested (250 passing) and documented in `flutter-app-guide.md`. What remains is Flutter
work, plus one item (§5 favourites) that neither side has started.

Prompted by seven observations from using the mobile app, plus an eighth (§8) raised afterwards. Every one was traced to source on both
sides before being written down here. The headline: **the DTOs match perfectly — every field in
`ApiContracts.cs` has a counterpart in `lib/data/models/`.** Nothing was ever broken at the wire
level.

The gaps were *behavioural*. They fall into three kinds, and the kind determines who fixes it:

| Kind | Meaning | Fix belongs to |
|---|---|---|
| **A — Client hasn't built it** | Backend supports it today; the client sends less than it could | Flutter only |
| **B — Backend enforces a rule it never publishes** | The server rejects or silently drops things the client cannot predict | Backend, then Flutter |
| **C — Neither side has it** | A genuinely new capability | Both |

---

## Summary table

| # | Observation | Kind | Backend | Flutter work |
|---|---|---|---|---|
| 1 | Can't add more than one item | **A** (mostly) | ✅ Publishes `maxLines` + `maxBuffetDrinks` | Multi-line composer |
| 2 | No guest view | **B** | ✅ `canOrderForGuests`; cap lifts on guest orders | Guest field, gated |
| 3 | Materials not grouped "mine" vs "buffet" | **A** | — nothing needed | Sectioned picker |
| 4 | First login asks for the current password | **C** | ✅ `/auth/set-initial-password` (+ web fixed) | Skip field when forced |
| 5 | "Usual" is just the last order | **C** | ⬜ **Not built** — favourites need a new table | Relabel to "آخر طلب" |
| 6 | Composer doesn't show a drink's extras | **B** | ✅ `allowedExtraItemIds` | Filter the extras row |
| 7 | Arabic notes stored as `?` | — | ⬜ **Deployed DB schema**, not code (see §7) | None |
| 8 | No double-portion warning | **B** | ✅ `variants[].ingredientItemIds` | Mark chip + hint |
| 9 | Can't declare an unlisted item | **B** | ✅ `POST /materials/declare-new` | "الصنف غير مدرج" form |

### What shipped on the backend

Every change is additive: each appends to a positional record or adds a route, so **nothing
is a breaking change** and the client can adopt them one at a time:

| Change | Where |
|---|---|
| `LoginResponse.canOrderForGuests` | `ApiContracts.cs` |
| `CatalogueItemDto.allowedExtraItemIds` | `ApiContracts.cs`, populated in `/catalogue` |
| `CatalogueResponse.maxLines` / `.maxBuffetDrinks` | `ApiContracts.cs`, from `OrderService` constants |
| `POST /auth/set-initial-password` | `EmployeeApi.cs` |
| Buffet cap lifts on privileged guest orders | `EmployeeApi.cs`, matching `OrdersController` |
| Forced change-password no longer asks for the old one | `AccountController.cs`, `ChangePassword.cshtml` |
| `VariantDto.ingredientItemIds` | `ApiContracts.cs`, populated in `/catalogue` |
| `POST /materials/declare-new` | `EmployeeApi.cs`, reusing `CreatePersonalItemAsync` |

Covered by `EmployeeApiParityTests.cs` — 16 tests over real HTTP, including the negative cases: a
settled user cannot reach the initial-password route, the route refuses a second call, and the guest
privilege alone does not lift the cap on an ordinary order. `OrderFulfillmentServiceTests.cs` gains
one more, pinning the double deduction that §8 exists to warn about.

---

## 1. Multiple items per order

**Kind A, with one real backend constraint. Backend done ✅ — Flutter work remains.**

The backend has always accepted multiple lines. `PlaceOrderApiRequest.Lines` is an
`IReadOnlyList<OrderLineDto>` and `OrderService.MaxLines = 25`.

The client is the limit. `ComposerState` holds **one** drink:

```dart
final CatalogueItemDto? drink;          // composer_controller.dart
```

and `toRequest()` hard-codes a single-element list. There is no cart.

**But there is a server rule the client must respect.** `OrderService.MaxBuffetDrinksPerOrder = 1`:
only **one** drink per ordinary order may come from buffet stock; every additional drink must come
from the requester's own materials, or `PlaceAsync` returns `OrderError.TooManyBuffetDrinks`.

Critically, this is counted on the source each line **resolved** to, not on the posted
`drinkFromOwn` flag — `BuildLine` silently falls back to company stock when someone claims personal
stock they do not hold. So a client that ticks "from my jar" on a jar the user does not own will be
rejected even though its own state said the order was legal.

**Flutter:** turn `ComposerState.drink` into `List<ComposerLine>`; add/remove/edit lines; cap at 25.
Compute a running count of lines that will resolve to buffet stock — a line counts as buffet
whenever `drinkFromOwn == false` **or** `ownServingsLeft <= 0` — and block the second one *in the
UI*, with a message explaining the rest must come from the user's own materials. Do not rely on
catching the 400: the failure arrives after the user has composed the whole order.

**Backend — done.** `/catalogue` now publishes both limits, so the client never hard-codes either:

```jsonc
{ "maxLines": 25, "maxBuffetDrinks": 1 }
```

They come straight from the `OrderService` constants, and a test asserts against those constants
rather than the literals — so if the cap is ever raised, the wire keeps reporting the truth.

---

## 2. Guest ordering

**Kind B. Backend done ✅ — Flutter work remains.**

`User.CanOrderForGuests` exists, and the API already reads it from the token's claims rather than
the request body:

```csharp
// EmployeeApi.cs, as it was — the privilege was read, but never published, and the
// cap was hard-coded off regardless of it.
CanOrderForGuests = principal.CanOrderForGuests(),
AllowMultipleBuffetDrinks = false,
```

`PlaceOrderApiRequest.OnBehalfOfName` is on the wire and the Flutter model carries it — but
**nothing in the app ever sets it.** The composer has no guest field.

The blocker is that **the client cannot discover whether the user holds the privilege.**
`LoginResponse` returns `Role` but not `CanOrderForGuests`, so the app cannot decide whether to show
a guest field, and a user without the privilege would get an unexplained rejection.

Note the second line above: the comment in `EmployeeApi.cs` says `AllowMultipleBuffetDrinks = false`
is stated explicitly *because* adding a guest screen later should be a deliberate edit on that line.
This is that moment. **A guest order that must obey the one-buffet-drink cap is close to useless** —
ordering for three visitors means two of the drinks must come from the employee's own jar. Decide
whether the guest privilege also lifts the cap.

**Backend — done.**

1. `LoginResponse.canOrderForGuests` is published (appended last, so the positional record stays
   source-compatible).
2. **The cap question is settled, by following the web app's existing precedent.**
   `OrdersController` already used `AllowMultipleBuffetDrinks = isGuestOrder && privileged`, so the
   API now matches:

   ```csharp
   AllowMultipleBuffetDrinks =
       !string.IsNullOrWhiteSpace(request.OnBehalfOfName) && principal.CanOrderForGuests(),
   ```

   **Both halves are required.** The privilege alone must not lift the cap on an ordinary order, or
   a privileged employee could quietly take ten buffet cups for themselves; and the guest name alone
   must not lift it, since that name comes from the request body, which the client controls.
   `PlaceAsync` separately rejects a guest name from an unprivileged caller. Two tests pin both
   halves.
3. **Still open, deliberately:** no `/auth/me`. The token lasts 30 days and carries the privilege as
   a claim, so a grant or revocation today does not reach an already-signed-in client until it gets
   a new token. Documented in §4.2 of the guide rather than papered over — worth revisiting if
   privileges start changing often.

**Flutter:** store the flag; show an optional "ordering for a guest" name field only when true; send
it as `onBehalfOfName`. `/orders/mine` and the staff queue already return and display it.

---

## 3. Group the composer by "my materials" vs "the buffet"

**Kind A. Nothing to do on the backend — Flutter only.**

`CatalogueItemDto` carries `hasOwnStock` and `ownServingsLeft` on **every** item — drinks, sugars
and extras alike. The composer uses them only for a chip tint and a servings counter; items from the
two sources are interleaved in one flat list.

**Backend:** none. Every field needed already ships.

**Flutter:** split each picker into two labelled sections — "من موادي" (`hasOwnStock == true`) and
"من البوفيه" — with owned items first. Two details worth getting right:

- **An item can be in both.** `hasOwnStock` means the user owns *some*; the buffet may stock it too.
  Group by which jar the order will draw from, not by which list the item appears in, and keep the
  existing per-item "from my jar" toggle as the thing that actually decides.
- **Owning it does not mean having any left.** `hasOwnStock` can be true with
  `ownServingsLeft == 0` — or negative, since the ledger permits negative balances by design. Show
  it under "من موادي" with the shortage warning; per the domain rules, **never disable it.**

This grouping also makes §1's buffet cap legible: the user can see which drinks count against it.

---

## 4. First login should not ask for the current password

**Kind C. Backend done ✅, web app fixed too — Flutter work remains.**

The observation is correct, and worth stating why it matters: the user has *just* proved they know
the password by logging in with it, seconds earlier. Asking again is friction with no security
value, and it is worst for exactly the users who hit it — people onboarding onto a seeded default
they were handed on a slip of paper.

Both clients do this today:

- **Flutter:** `change_password_screen.dart` renders the current-password field unconditionally;
  `AuthStage.mustChangePassword` only changes the banner text.
- **Web:** `ForcePasswordChangeFilter` pins the user to `ChangePassword`, whose view takes
  `IsForced` — but the POST still calls `auth.VerifyAsync(username, model.CurrentPassword, ct)`.

The backend leaves them no choice: `/auth/change-password` **always** verifies `CurrentPassword` and
returns "كلمة المرور الحالية غير صحيحة." when it fails. This cannot be fixed client-side.

**Backend — done. A separate endpoint, rather than weakening the existing one:**

```
POST /api/v1/auth/set-initial-password   { "newPassword": "…" }
```

- Requires a valid bearer token, **and** rejects with `400` unless that token's
  `must_change_password` claim is `"true"`. The claim is already minted by `JwtTokenService`.
- Applies the same 8-character minimum.
- Calls `auth.SetPasswordAsync`, which clears `MustChangePassword`.
- Audits distinctly from a voluntary change.

**Why a second endpoint and not a nullable `CurrentPassword` on the existing one:** making the field
optional means a bug in the claim check silently degrades *every* password change into an
unauthenticated one. A separate route fails closed — if its guard breaks, the route is wrong for
everyone rather than quietly permissive for everyone. Leave `/auth/change-password` untouched for
voluntary changes from the settings screen.

**The web side was fixed to match**, so the two clients do not diverge on an auth rule: when
`IsForced`, `ChangePassword.cshtml` omits the field and `AccountController` skips `VerifyAsync`.
`IsForced` is re-read from the claim on every POST, never trusted from the hidden form field, so a
forged value cannot skip the check on a voluntary change. The `[Required]` on `CurrentPassword`
stays and its model error is cleared on the forced path only — dropping the attribute would have let
a voluntary change through with no current password at all.

**Flutter:** when `stage == AuthStage.mustChangePassword`, hide the current-password field and call
the new endpoint; keep the existing screen and endpoint for voluntary changes from settings.

---

## 5. "Usual order" — and favourites

**Kind C. ⬜ Not built on either side.** Favourites need a new table, so this is the one
item deliberately left for a later pass. The guide has been relabelled in the meantime.

The reading is correct: it is the last order, nothing more.

```csharp
// EmployeeApi.cs
var last = orders.FirstOrDefault(o => o.Status != OrderStatus.Cancelled && o.Lines.Count > 0);
```

One non-cancelled order, most recent. No frequency, no weighting. Order something unusual once for a
visitor and it becomes your "usual" until you order again.

**The irony is that a real implementation already exists.** `ReportingService.EmployeePreferences`
computes the genuine article — most-ordered drink, mean sugar rounded to one decimal, and extras
appearing on **a third or more** of the user's drinks, suppressed entirely below
`MinimumPreferenceSample = 3` so a single order is never mistaken for a habit. It is used for admin
reporting only and never surfaced to the employee who generated it.

The instinct to prefer explicit favourites over a guess is the better product answer, and the two
should coexist. Favourites are *stated*; the computed usual is a *suggestion* for someone who has
never saved one. Recommendation: ship both, label them differently, and never call a computed guess
"favourite".

**Backend:**

1. **Favourites** — new table `OrderFavourites` (`FavouriteId`, `Username`, `NameAr`,
   `CreatedAtUtc`) with child lines reusing the `OrderLineDto` shape.
   - `GET /api/v1/favourites` → `IReadOnlyList<FavouriteOrderDto>`
   - `POST /api/v1/favourites` `{ nameAr, lines }` → `201`
   - `DELETE /api/v1/favourites/{id}` → `204`, ownership-checked, `404` (not `403`) on someone
     else's, matching the existing convention on orders.
   - Add `bool SaveAsFavourite` + `string? FavouriteName` to `PlaceOrderApiRequest` (appended last)
     so the composer's toggle saves in the same round trip.
   - **Store item ids, not just names**, so a favourite can be re-ordered rather than only read —
     and re-validate on replay, since an item may since have been deactivated. A favourite naming a
     dead item should degrade to a warning, not a `500`.
2. **Keep `Usual`, add `Favourites`.** `UsualOrderDto.Summary` is Arabic prose built for display;
   keep it, and add `IReadOnlyList<FavouriteOrderDto> Favourites` to `CatalogueResponse` alongside it.
3. **Optionally** promote `EmployeePreferences` into the usual computation, so `Usual` becomes the
   real habit instead of the last order. Cheap — the algorithm is written and tested.

**Flutter:** a favourites strip above the drink grid; a "احفظ كطلب مفضل" toggle in the composer with
an optional name; long-press to delete. Keep the existing one-tap repeat for `Usual`, labelled as
"آخر طلب" (*last order*) until the computed version ships — the current label overpromises.

---

## 6. The composer does not show which extras a drink allows

**Kind B. Backend done ✅ — Flutter work remains.** The sharpest mismatch of the seven, because
the backend silently drops what it will not accept.

`ItemAllowedExtras` exists (migration `20260812132920_AddPerDrinkAllowedExtras`), an admin edits it
in `InventoryController`, and `OrderService` enforces it on every order:

```csharp
// OrderService.cs — the order form hides extras a drink does not permit, but hiding a
// checkbox stops nobody posting its value, and an unfiltered extra would deduct real
// stock for something the drink never offered.
var allowedExtrasByDrink = (await repository.GetAllowedExtrasAsync(ct)) …
```

That comment describes the **web** order form, which does hide them. The mobile client has no way
to: `CatalogueItemDto` exposes `Variants` but **not** allowed extras, so the composer shows every
extra for every drink.

**This fails quietly, which makes it worse than a rejection.** A disallowed extra is filtered out
inside `BuildLine` — the order still succeeds, minus the milk the user asked for. They find out when
the drink arrives wrong. Note also the documented default: *a drink absent from the table permits
**all** extras* (`IBuffetRepository`), so the new field must distinguish "no restrictions" from "no
extras allowed" — a null/absent list means unrestricted, an empty list means none.

**Backend — done.** Added to `CatalogueItemDto` (appended last):

```csharp
/// Null when the drink permits every extra — the default for a drink with no configured
/// restriction. An empty list means no extras are allowed at all. Never conflate the two.
IReadOnlyList<int>? AllowedExtraItemIds
```

Populated from `GetAllowedExtrasAsync` in the `/catalogue` handler — one extra query for the whole
response, already grouped by item. Null on sugars and extras, which take no extras of their own.

**Flutter:** filter the extras row by the selected drink; when the list is null show all; when it is
empty hide the row entirely rather than showing an empty section. Clear any selected extra that the
newly-chosen drink disallows — otherwise switching drinks silently carries a selection that will be
dropped server-side, reproducing the same bug from the other direction.

---

## 7. Arabic notes stored as `?`

Not a parity issue and **not a code defect on either side.** Every text column in the EF model is
`nvarchar`; the deployed database's schema disagrees with the model because `MigrateOnStartup: false`
and those tables were created by other means. The fix is `ALTER TABLE` against the deployed database.

Full analysis: `backend-request-arabic-encoding.md` in the Flutter repo, and the correction to its
stated cause in the review that accompanies this document.

---

## What's left

The backend is no longer the blocker on anything. Remaining work, in the order that makes sense:

1. **§6 + §8 — the extras row.** One piece of work: §6 decides *which* chips appear, §8 decides
   which of them are *marked*, and both hang off the selected drink and preparation. Smallest
   change, and between them they stop a wrong drink and a silent double charge. Do this first.
2. **§4 — call `/auth/set-initial-password`** on the forced path and hide the current-password
   field. Self-contained.
3. **§1 + §3 — the multi-line composer and the grouped picker.** One piece of work: grouping by
   source is what makes the buffet cap comprehensible, so building either alone is wasted effort.
4. **§2 — the guest field**, gated on `canOrderForGuests`, with the relaxed cap when a guest is
   named. Depends on §1 being done first.
5. **§9 — the "الصنف غير مدرج" form.** Independent of the composer work: it lives in the 
   declare sheet, not the order screen, so it can be built at any point.
6. **§5 — favourites.** Not started on either side. Needs a new table and endpoints before any
   client work; until then the guide relabels "الطلب المعتاد" to "آخر طلب", which is what the field
   actually contains.
7. **§7 — the deployed database's collation.** Independent of all of the above, and the only one
   that blocks users outright today: Arabic free text cannot be written at all until it is fixed.

Every backend change appended to an existing positional record or added a new route. **None is a
breaking change**, so the client can adopt them one at a time and in any order.

---

## 8. No warning that an extra doubles a portion

**Kind B. Backend done ✅ — Flutter work remains.** Raised after the first seven, and the same shape
as §6: a rule enforced server-side and invisible to the client. The difference is the failure mode —
a disallowed extra is *dropped*, while this one is *charged twice*.

Picking **milk** as an extra on a **فرنساوي** is a double portion. The preparation already pours
milk, so the order deducts it twice, and `OrderFulfillmentService` adds both under the same key:

```csharp
// Recipe ingredients: the milk in a قهوة فرنساوي.
foreach (var ingredient in variant.Ingredients) { Add(required, Key(...), ...); }
```

Measured, not assumed: 22 g from the recipe plus milk's own 30 g serving as an extra is **52 g**,
now pinned by `Plan_MilkChosenAsAnExtraOnFrenchCoffee_DeductsTwoPortions`.

The doubling is *correct* — two pours, two deductions — but as the web's own comment puts it, it is
"the kind of correct that looks like a bug on the stock report if nobody said so first". So the web
says so first, on the chip and under the extras row. The mobile client could not, because
`VariantDto` was four scalars and `ItemVariant.Ingredients` stopped at the API boundary.

**Backend — done.** `VariantDto.IngredientItemIds`, appended last. It cost nothing: the `/catalogue`
handler already loads these variants and `GetVariantsAsync` already does
`.Include(v => v.Ingredients)`, so this is a projection change with no extra query.

Empty rather than null, as requested — unlike `AllowedExtraItemIds` there is no "unrestricted" case,
and a preparation that pours nothing extra is exactly what `[]` describes.

**Flutter:** mark the affected chip while that preparation is selected — the mark **moves** when the
user switches preparation, since milk is in one recipe and not another — and show a hint under the
row once such an extra is ticked. **Annotate, never filter, and never block:** an ingredient is part
of the recipe and cannot be declined, which is what separates it from `allowedExtraItemIds`, and a
double portion is a legitimate thing to order. Same rule as a shortage — say what will happen and
let the user decide.

---

## 9. An employee cannot declare an item the buffet does not carry

**Kind B. Backend done ✅ — Flutter work remains.** A capability the web had and the API did not
expose. The report was right on every point, including that `CreatePersonalItemAsync` had exactly
one caller in the solution and it was `MyMaterialsController`.

Worth restating why it matters more here than on the web: bringing a jar in is a *physical* act
that happens away from a desk. The employee is standing in the kitchen holding the packet — which
is exactly when they open the phone, and exactly when they find their item is not in the list.

**Backend — done.** `POST /materials/declare-new`, taking `DeclareNewMaterialRequest`. **Option B**
of the two proposed, for the reason the report itself gave: a route that creates catalogue rows and
a route that only tops up existing ones should not be reachable from the same request body, and
making `ItemId` nullable would mean a request that lost its id quietly creates a duplicate item
instead of failing. Same reasoning as `/auth/set-initial-password`.

Both details the report asked to have stated in the contract are stated, in the DTO's own XML docs
so they survive the next reader: the item is created **unpublished** and will not appear in
`/catalogue`, and `category` travels **by name**.

### One thing the request did not account for

`quantity` on this route is **packets, not base units** — a deliberate divergence from
`/materials/declare`.

The web form has counted packets since its base-unit field was removed, and its comment says why:
asking employees to reason in grams — the admin's unit — meant a number left sitting in the field
silently inflated the declaration. For a brand-new item the objection is sharper still, because the
caller has *just* said what one packet holds in the same request. Asking again in grams invites the
two numbers to disagree, and the server has no way to tell which one was meant.

So `unitsPerPackage: 200, quantity: 2` declares 400 g. Label the field "عدد العبوات". This is the
one mistake here that is **silent** — send grams and it declares 2 g without erroring — which is
why it leads the guide's §7.5 note.

Validation runs entirely before the item is created, so a rejected request leaves no orphan
catalogue row: empty name, unknown category, and a non-positive `unitsPerPackage`,
`unitsPerServing` or `quantity` each return `400`. A declaration that fails after the item exists
retires it, matching the web's own cleanup.

**Not built, as agreed:** the image. It needs multipart, and the category glyph already covers it.

**Flutter:** add «الصنف غير مدرج» as the picker's last entry — last so the common case, topping up
something known, stays the default — revealing the five fields. On success say
"بانتظار تأكيد الموظف", and do **not** refetch `/catalogue` expecting the item to appear.

