# Backend request: `StartedAtUtc` on `OrderSummaryDto`

**Repo:** `../buffet_app` (ASP.NET Core 10)
**Status: SHIPPED in the backend repo 2026-09-27** (commits `4c91a7e`, `19e80f0`, `9337d8d`; contracts synced into `docs/contracts/`). **Deployed** to digitalbuffet.runasp.net and verified from the app the same day. Closed.
**Severity:** low. This is cosmetic: it adds one timestamp to the tracking timeline.
**Raised:** 2026-09-24, from the Figma redesign (see [figma-redesign.md](figma-redesign.md)).

---

## Why

The redesigned tracking screen is a vertical timeline, **Sent → Being prepared → Ready →
Completed**, with a time beside each step that has happened. `OrderSummaryDto` has three of the
four times:

| Step | Field |
|---|---|
| Sent | `CreatedAtUtc` |
| Being prepared | **missing** |
| Ready | `ReadyAtUtc` |
| Completed / Cancelled | `HandledAtUtc` |

The value already exists:

- `OrderHeader.StartedAtUtc` (`src/BuffetApp.Core/Models/Order.cs:26`), added in migration
  `20260811140630_AddOrderStartedTimestamp`.
- It is set in `SqlBuffetRepository.cs:685` when preparation starts. Both
  `POST /staff/orders/{id}/start` and the web queue reach that code.
- The reports already use it for queue and preparation minutes (`ReportingService.cs:415-419`).

It is simply not projected onto the wire.

## Requested change

- `OrderSummaryDto`: add `DateTime? StartedAtUtc`, **null** until preparation starts.
- `EmployeeApi.cs` `ToSummary` (~line 790): pass `order.StartedAtUtc`.

It is additive: existing clients ignore an unknown field.

## Note for the implementer

The step can be skipped. An order can be "served straight from `Pending`" (the wording in the
`ReleaseClaimAsync` remarks, `IBuffetRepository.cs:176-181`), and the staff queue's "Ready and
delivered" action does exactly that, so an order can reach `Ready` with `StartedAtUtc` still null. Please keep it null in that case rather than backfilling it with
`ReadyAtUtc`. The client shows the step as passed without a time, which is the truth.

## What the client will do

Until the field appears in `docs/contracts/ApiContracts.cs`, the "Being prepared" step shows no
time. Every other step is unaffected.
