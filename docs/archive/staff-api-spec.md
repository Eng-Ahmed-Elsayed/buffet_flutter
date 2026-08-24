# Staff API — endpoints to add before the mobile app ships

> **Status: implemented.** `src/BuffetApp.Web/Api/StaffApi.cs`, mapped in `Program.cs`, covered by
> `tests/BuffetApp.Tests/StaffApiTests.cs`. Two things landed differently from the specification
> below, both deliberate and both marked inline: the declaration endpoints are **admin-only**, and
> `StaffOrderLineDto.SugarNameAr` is always null. See § Deviations at the end.

The Flutter client covers the employee **and staff** views. The employee half is fully served by
the existing `/api/v1`. The staff half is not: the queue and its actions exist only as MVC actions
in `src/BuffetApp.Web/Controllers/StaffController.cs`, which return HTML.

This document specifies the JSON endpoints that close that gap. **It is a backend work item, not a
blocker on the app** — the Flutter team builds the staff screens against these contracts now, and
they are wired to a live server before deployment.

Related: [flutter-app-guide.md](flutter-app-guide.md) — the client-side reference.

---

## Why the existing endpoints cannot be reused

A staff member can already obtain a token: `POST /auth/login` authenticates on credentials without
checking the role, and the token carries `role: "Staff"`. But every order endpoint under
`/api/v1` is scoped to the caller:

| Endpoint | Behaviour for staff | Why it fails |
|---|---|---|
| `GET /orders/mine` | Returns the staff member's own drinks | Filters on `RequesterUsername == caller` |
| `GET /orders/{id}` | **404** on any order they did not place | Ownership check; a 403 would confirm existence |
| `POST /orders/{id}/cancel` | Rejected | Calls `CancelOwnAsync`, which is ownership-checked |

These are correct for employees and must not be loosened. The staff surface is additive.

---

## Placement and authorisation

A new `src/BuffetApp.Web/Api/StaffApi.cs`, mapped alongside `MapEmployeeApi` in `Program.cs`,
following the existing pattern exactly:

```csharp
var staff = app.MapGroup("/api/v1/staff")
    .WithTags("Staff")
    .RequireAuthorization(new AuthorizeAttribute
    {
        AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme,
        Policy = AuthConstants.StaffOrAdmin
    });
```

Bearer-only, for the same reason the employee group is: these endpoints have no antiforgery
tokens, so accepting ambient cookie credentials would hand them the CSRF exposure the MVC forms
are protected against.

`StaffOrAdmin` rather than `StaffOnly` — an admin covering the counter should not be locked out,
which is how the web screens already behave.

---

## Endpoints

### `GET /api/v1/staff/queue`

The live queue: `Pending` and `InProgress`, oldest first. Returns `StaffOrderDto[]` (§ Contracts).

Optional `?status=` filter accepting the status name; omitted means the live queue. Cap the page
the way `/orders/mine` does — `take`, default 50, maximum 200.

### `GET /api/v1/staff/orders/{id}`

Full detail for **any** order — no ownership filter. Returns `StaffOrderDto`, 404 when the id does
not exist.

### `POST /api/v1/staff/orders/{id}/start`

`Pending → InProgress`. Delegates to the same path as `StaffController.Start`. Returns `204`, or
`400` with `ApiError` when the transition is invalid.

### `POST /api/v1/staff/orders/{id}/ready`

`InProgress → Ready`, and with `?deliverNow=true` continues straight to `Completed`.

> **This endpoint deducts stock.** It must call `OrderServingService`, which is the only path
> permitted to do so and the only place that knows whose jar each component comes from. Stamping
> the status directly writes a served drink that never touched the ledger.

Returns `200` with `ServeResultDto` — the shortage warnings belong in the response body, because
staff need to see them and shortages **never block**:

```jsonc
{ "orderId": 41, "status": "Ready", "warnings": [
  { "itemId": 7, "nameAr": "حليب", "ownerDisplayName": "أحمد", "shortfall": 12.0, "unit": "جرام" }
] }
```

An empty `warnings` array is the normal case. A non-empty one is **not** an error — return `200`,
not `400`.

### `POST /api/v1/staff/orders/{id}/complete`

`Ready → Completed` — handed over. Returns `204`.

### `POST /api/v1/staff/orders/{id}/cancel`

Body `{ "reason": "…" }`. Returns `204`.

> Cancelling a **`Ready`** order reverses the consumption and re-books it as waste, so the balance
> is unchanged but nobody is credited with a drink they never received. That logic already exists —
> call it, do not reimplement it.

### `GET /api/v1/staff/declarations`

> **Admin-only, not `StaffOrAdmin`.** These three endpoints sit in a nested group with a tighter
> policy than the one around them. Confirming a handover creates stock out of nothing but somebody's
> word, and the person who takes the jar should not also be the only person who signs for it — the
> web screens narrowed to admin for that reason. A staff token gets `403`.

Personal-material declarations awaiting confirmation, oldest first. Returns `DeclarationDto[]`.

### `POST /api/v1/staff/declarations/{id}/confirm`

> **This is what creates stock.** Employee declares, staff confirms; a declaration alone creates
> nothing. Delegates to `PersonalStockService`, which books the opening balance as a ledger
> movement rather than writing the quantity — writing both double-counts.

Body `{ "quantity": 500.0 }` — optional. Omitted confirms the declared amount; supplied confirms a
corrected amount, for when the jar that arrived is not the jar that was declared. Returns `204`.

### `POST /api/v1/staff/declarations/{id}/reject`

Body `{ "reason": "…" }`. Returns `204`. Notifies the employee (`DeclarationRejected`).

---

## Contracts

Add to `ApiContracts.cs`, or a sibling `StaffContracts.cs`. Deliberately separate from the domain
models, like the existing DTOs: an entity reshaped for an internal reason must not silently change
a contract a shipped app depends on.

```csharp
/// <summary>A queue entry, seen from behind the counter.</summary>
public sealed record StaffOrderDto(
    int OrderId,
    string Status,
    DateTime CreatedAtUtc,
    DateTime? ReadyAtUtc,
    /// <summary>Who ordered it — staff need the name, not just the username.</summary>
    string RequesterDisplayName,
    string Department,
    string LocationText,
    string? OnBehalfOfName,
    string Notes,
    /// <summary>Seconds since the order was placed, for the ageing indicator.</summary>
    int WaitingSeconds,
    IReadOnlyList<StaffOrderLineDto> Lines);

/// <summary>
/// One drink to make. Unlike the employee's OrderLineDto, sources are named rather than
/// flattened to "from own" booleans — those are computed relative to the caller, which is
/// meaningless to staff. The queue's whole job is saying which jar to reach for.
/// </summary>
public sealed record StaffOrderLineDto(
    int DrinkItemId,
    string DrinkNameAr,
    string? VariantNameAr,
    int SugarSpoons,
    string? SugarNameAr,
    IReadOnlyList<string> ExtraNamesAr,
    string? LineNote,
    /// <summary>Empty string for company stock; otherwise the owner's display name.</summary>
    string DrinkSourceOwnerName,
    string SugarSourceOwnerName,
    IReadOnlyList<StaffExtraSourceDto> ExtraSources);

public sealed record StaffExtraSourceDto(int ItemId, string NameAr, string SourceOwnerName);

public sealed record ServeResultDto(
    int OrderId,
    string Status,
    IReadOnlyList<StockWarningDto> Warnings);

/// <param name="Shortfall">How far below zero the balance went. Positive number.</param>
public sealed record StockWarningDto(
    int ItemId, string NameAr, string OwnerDisplayName, decimal Shortfall, string Unit);

public sealed record DeclarationDto(
    int DeclarationId,
    string OwnerDisplayName,
    int ItemId,
    string NameAr,
    decimal Quantity,
    string Unit,
    string Note,
    DateTime CreatedAtUtc);

public sealed record CancelOrderRequest(string Reason);
public sealed record ConfirmDeclarationRequest(decimal? Quantity);
public sealed record RejectDeclarationRequest(string Reason);
```

---

## Constraints the implementation must hold

1. **`/ready` goes through `OrderServingService`.** The single path that deducts stock. No
   endpoint may stamp `Ready` or `Completed` directly.
2. **Cancelling a `Ready` order reverses and re-books as waste.** Existing logic; call it.
3. **Source owner is named per line.** Without it the queue cannot tell staff which jar to use,
   which is the screen's entire purpose.
4. **Shortages return `200` with warnings, never `400`.** Physical and recorded stock drift, and
   halting service is worse than a negative number an admin reconciles later.
5. **Every action writes an audit entry**, matching the employee endpoints' `"(تطبيق)"` suffix
   convention so mobile actions are distinguishable from web ones in the audit log.
6. **Reuse the services, add no business logic.** The API is a second doorway onto the same house.

## Testing

Mirror the existing API tests: a staff token reaches the queue; an **employee** token gets `403`
on every `/staff/*` endpoint; `/ready` deducts exactly once and returns warnings rather than
failing on a shortage; cancelling a `Ready` order leaves the balance unchanged and books waste;
confirming a declaration creates the balance as a ledger movement counted exactly once.

All of the above is covered by `tests/BuffetApp.Tests/StaffApiTests.cs` (23 tests). There were no
existing API tests to mirror, so `StaffApiFactory` was added: it boots the real application over an
in-memory HTTP server against a throwaway LocalDB database, and the tests sign in through the real
`/auth/login`. Driving real HTTP is the point — authorisation does not run when an endpoint
delegate is invoked as a plain method, so a suite built that way would still pass with the
authorisation stripped out.

Two traps that cost time and will cost it again:

- **The database must exist before the host starts.** `Program` runs the store initialiser during
  startup, and touching `factory.Services` is what triggers startup — so creating the schema
  through a scope resolved from the factory is already too late and fails with "cannot open
  database".
- **Drop the database after disposing the host, and clear the connection pools first.** Pooled
  connections outlive the host that opened them, and SQL Server will not drop a database that still
  has sessions on it.

---

## Deviations from this specification

1. **Declaration endpoints are `AdminOnly`,** not `StaffOrAdmin` as § Placement implies. Commit
   `254661a` deliberately narrowed receiving materials to admin; mapping these as staff would have
   re-opened through the API exactly what was closed on the web, leaving the two surfaces
   disagreeing about who may create stock.
2. **`StaffOrderLineDto.SugarNameAr` is always null.** Unlike the drink's name, the sugar's name is
   not denormalized onto the order line, so filling it would mean a catalogue lookup per line on
   every queue card. The spoon count and the source owner — which staff actually act on — are
   populated. The field is kept in the contract so it can be filled later without a breaking change.
3. **`PersonalStockService.ConfirmAsync` gained a `confirmedQuantity` parameter.** The spec's
   corrected-amount feature had no service support; it is implemented there rather than in the
   endpoint so the ledger stays the single path that creates stock. The correction is written to
   the declaration as well, so the record matches the balance it produced.
4. **`GET /staff/queue` returns `Pending` and `InProgress` only,** as specified — note this differs
   from the MVC queue, which also includes `Ready` because it is the screen the handover button
   lives on.
