# Backend request: let an employee declare an item the buffet does not carry

**Raised:** 2026-08-20. **Resolved:** 2026-08-20 — `POST /materials/declare-new` shipped and the
sheet uses it. Kept as the record of why the endpoint exists.

**Was:** "my item isn't in the list" in the mobile declare sheet. **Kind:** B — a capability the
web had and the API did not expose.

> **Shipped as Option B**, the separate endpoint. Two things went beyond what was asked and are
> worth knowing: `quantity` is in **packages**, not base units as on `/materials/declare` — the
> server multiplies by `unitsPerPackage` — and a failed declaration **deletes the item it just
> created**, so a rejected request leaves no orphan catalogue row.

## The gap

On the web, an employee bringing in their own coffee that the buffet does not stock can add it.
The item picker's last option is **«الصنف غير مدرج»**, which reveals a fieldset for the new item's
details:

```razor
@* Value 0 tells the controller to create a private item. Last in the list so the common case
   — topping up something known — stays the default. *@
<option value="0">@T["ItemNotListed"]</option>
```

`MyMaterialsController.Declare` then branches on `itemId <= 0` and calls
`PersonalStockService.CreatePersonalItemAsync` before recording the declaration.

**The API cannot do this.** `DeclareMaterialRequest` is:

```csharp
public sealed record DeclareMaterialRequest(int ItemId, decimal Quantity, string? Note);
```

`ItemId` is an existing item's id and nothing else — `/materials/declare` looks it up and returns
`400 "الصنف غير متاح."` when it does not resolve, so `0` is a rejection rather than a signal:

```csharp
var item = await repository.FindItemAsync(request.ItemId, ct);
if (item is null || !item.IsActive || !item.IsVisibleTo(principal.Username()))
    return Results.Json(new ApiError("الصنف غير متاح."), statusCode: 400);
```

`CreatePersonalItemAsync` has **exactly one caller in the whole solution**, and it is the MVC
controller (`MyMaterialsController.cs:86`). No API path reaches it.

So the answer to "is this the API or the client?" is: **the API.** The mobile picker can only
offer what `/catalogue` returns, and there is no endpoint that would accept a new name.

## Why this matters more on mobile than on the web

Bringing a jar in is a *physical* act that happens away from a desk. The employee is standing in
the kitchen with the packet in their hand — that is exactly when they open the phone, and exactly
when they discover their item is not in the list and there is nothing they can do about it. On the
web they would at least be sitting down.

## Requested change

Either shape works; the second is smaller.

**Option A — a field on the existing request.** Make `ItemId` nullable and add the new-item
details, mirroring the controller's branch:

```csharp
public sealed record DeclareMaterialRequest(
    int? ItemId,
    decimal Quantity,
    string? Note,
    NewPersonalItemDto? NewItem);

/// <summary>Details for an item the buffet does not carry. Ignored when ItemId is set.</summary>
public sealed record NewPersonalItemDto(
    string NameAr,
    string Category,          // "Drink" | "Sugar" | "Extra" — by NAME, as everywhere else
    string Unit,
    decimal UnitsPerPackage,
    decimal UnitsPerServing);
```

Reject a request carrying both or neither, so the two cases stay distinguishable.

**Option B — a separate endpoint**, `POST /materials/declare-new`, taking the same body without
`ItemId`. Fails closed the way `/auth/set-initial-password` does: a fault in one route cannot make
the other quietly permissive.

Either way the response should stay **`202 Accepted`** with the declaration id, for the same
reason it already is — staff still have to confirm the jar physically arrived.

### Two details worth stating in the contract

1. **The item is created unpublished**, per `CreatePersonalItemAsync`'s own docs — invisible even
   to its owner's order screen until staff confirm receipt. The client must therefore **not**
   expect the new item to appear in `/catalogue` after a successful call, and should say
   "awaiting confirmation" rather than "added". This is the same `202` semantics we already
   honour, and it needs to be explicit or a client will treat the empty catalogue as a bug.
2. **Category by name, never ordinal** — as with order status and role. The web posts an
   `ItemCategory` enum; the wire should carry `"Drink"`.

### Not requested: the image

The web form also accepts `newImage`. I have deliberately left it out — it needs multipart, and a
photograph is not the part that unblocks anybody. An item created without one falls back to the
category glyph, which the client already handles. Worth a separate request later if it turns out
people want it.

## What shipped

The picker's last entry is «الصنف غير مدرج», which reveals name, type, unit, package contents and
amount per cup — and switches the quantity field's label from the item's unit to **عدد العبوات**.

The unit switch is the part that needed care. The same field means base units on one endpoint and
packages on the other, and getting it wrong is **silent**: it would declare 2g of a 200g jar and
nothing would error. The label changes with the mode, and a test pins it.

`category` is sent by name — `"Drink"`, never `0`, which the server cannot distinguish from an
unset field.
