# Backend request: pickup or delivery, chosen per order, and "I picked it up"

**Repo:** `../buffet_app` (ASP.NET Core 10)
**Status: SHIPPED in the backend repo 2026-09-27** (commits `4c91a7e`, `19e80f0`, `9337d8d`; contracts synced into `docs/contracts/`). **Deployed** to digitalbuffet.runasp.net and verified from the app the same day. Closed.
**Severity:** medium. This is a **new business capability**, decided 2026-09-24. It is not a bug.
**Raised:** 2026-09-24, from the Figma redesign (see [figma-redesign.md](figma-redesign.md), D5–D6).

---

## Why

Both things happen in practice. Sometimes the employee walks to the kitchen for their drink, and
sometimes staff carry it to a desk or a meeting room. The system has no record of which one was
meant:

- `PlaceOrderApiRequest` carries an optional location and nothing else. `ResolveLocationAsync`
  (`OrderService.cs:401`) accepts an empty one.
- Staff cannot tell from the queue card whether to walk the drink over or leave it on the counter.
- The Ready notification (`NotificationService.cs:29`) cannot say the right thing. It currently
  reads «جاهز للاستلام».
- The `OrderHeader.StartedAtUtc` remarks (`Order.cs:20-23`) already call "straight to Ready" the
  common path "when the employee is standing at the counter". Pickup is normal today; it is just
  not recorded.

The new design also gives the employee a green **"Pickup Order"** button on the tracking screen.
Its job is to let the employee close their own pickup order when they collect it, which also covers
the orders staff forget to mark. There is no employee endpoint for that today; only staff complete
orders (`StaffApi.cs:250`).

## Requested changes

### 1. Model

- `Enums.cs`: `public enum FulfilmentMode { Pickup, Delivery }`. On the wire it is the **string
  name**, the same as `OrderStatus`.
- `OrderHeader`: `public FulfilmentMode? Fulfilment { get; set; }`, plus a migration.
  - **Existing rows stay null.** A null means "not recorded" and reads as neutral everywhere.
    Please do not backfill: nothing on an old order says which one it was.

### 2. Placing an order

- `PlaceOrderApiRequest`: append `string? Fulfilment = null` **at the end**, so the positional
  record stays additive. Add the same to `PlaceOrderRequest` (`OrderService.cs:~36-43`).
- When it is **omitted**, infer it, so the web form and older app builds keep working unchanged:
  `Delivery` when the resolved location is non-empty, otherwise `Pickup`.
- **Validation**, returned as localised `400`s through a new `OrderError` key in
  `SharedResource.ar.resx` / `.en.resx`:
  - An unknown value is rejected.
  - `Delivery` with no location is rejected. For example: «اختر مكان التوصيل أو اختر الاستلام من
    المطبخ». **Validate against the resolved location** (the text `ResolveLocationAsync` returns),
    not the raw request. An unknown `LocationId` with blank text resolves to an empty location
    (`OrderService.cs:401-418`) and must fail, just as a missing one does. An *inactive* one still
    resolves to its name (the lookup uses `activeOnly: false`, line 408) and passes. That is
    deliberate: the place still exists.
- `Pickup` **with** a location is accepted, and the location is kept. It is harmless, and it tells
  staff where the person sits.
- A staff member's own auto-served order (`PlaceOrderResponse.AutoServed`) completes in the same
  call, so its mode does not matter; inferring is fine.

### 3. Reading it back

Append a `string? Fulfilment` (null for legacy orders) to both of these:

- `OrderSummaryDto`, mapped in `ToSummary` (`EmployeeApi.cs:790`).
- `StaffOrderDto`, mapped in `ToStaffDto` (`StaffApi.cs:549`).

### 4. The web app

- Order form: `Views/Orders/_OrderFormFields.cshtml`, shared by `Create` and `CreateForGuest`.
  Add a two-option choice beside the location field. The existing `LastLocationText` prefill keeps
  working.
- Staff queue: `Views/Staff/Queue.cshtml` and `Details.cshtml` get a visible **Pickup** / **Deliver
  to …** badge on each order.
- Employee views: `Views/Orders/Details.cshtml` and `MyOrders.cshtml` show the choice.

### 5. The Ready notification (`NotificationService.cs:29`)

The message becomes per mode. The push title «مشروبك جاهز» stays.

| Mode | Message |
|---|---|
| `Pickup` | «طلبك رقم N جاهز، تفضل باستلامه من المطبخ.» |
| `Delivery` | «طلبك رقم N جاهز وسيصلك قريبًا — {location}.» |
| null (legacy) | unchanged: «طلبك رقم N جاهز للاستلام — {location}.» |

"Will reach you shortly" rather than "on its way": Ready means the drink is made, not that anybody
has left with it.

### 6. `POST /orders/{id}/collected`, the employee confirming a pickup

Model it on `POST /orders/{id}/cancel` (`EmployeeApi.cs:409-429`) and `CancelOwnAsync`
(`OrderService.cs:276`). Add a `CollectOwnAsync(orderId, username)`:

| Case | Result |
|---|---|
| Order not found | `OrderError.OrderNotFound` → localised `400`, as cancel does |
| Not the caller's order | `OrderError.NotYourOrder` → localised `400`, as cancel does |
| `Fulfilment != Pickup` (including null) | new `OrderError` key → localised `400` |
| Status is `Ready` | `UpdateOrderStatusAsync(orderId, Completed, username, expectedCurrent: [Ready])` → `204` |
| Status already `Completed` | `204`, a no-op, so a retry after a dropped response is harmless |
| `Pending` or `InProgress` | new `OrderError` key ("not ready yet") → localised `400` |
| `Cancelled` | new `OrderError` key ("no longer open") → localised `400` |
| **The update returns `false`** (staff completed or cancelled it between the read and the write) | **Re-read the order** and answer from its new status: `Completed` → `204`, `Cancelled` → the "no longer open" `400` |

Notes for the implementer:

- **Stock is untouched.** It was deducted at `Ready`, the only path that writes ledger rows.
  Completing is only the handover.
- `HandledByUsername` becomes the requester. The employee's own cancel already does exactly this
  (`CancelOwnAsync` passes `username` as `handledBy`), and no service or report reads
  `HandledByUsername` today (grepped 2026-09-24). So there is no reporting impact now; flag it if a
  "handled by staff" report is ever added.
- Write an audit entry, as cancel does: «استلام طلب (تطبيق)».
- **No notification.** The employee is the one acting.
- `Views/Orders/Details.cshtml:36` displays `HandledByUsername` as "Handled by", so an employee's
  own pickup shows their own name there. That is true, but consider labelling it "Collected by the
  requester" in that case.
- Staff can still complete a pickup order from the handover list, as today.

### 7. Make staff "complete" idempotent (needed by 6)

Today `POST /staff/orders/{id}/complete` (`StaffApi.cs:250-275`) accepts only `Ready`, and on
anything else returns `400 MsgNotReadyForHandover`. The web's `StaffController.Complete`
(`StaffController.cs:187`) guards the same way.

Once employees can close their own pickups, the common race is:

1. The employee taps "I picked it up".
2. The staff member, who still has the card on screen, taps "Mark delivered".
3. The staff member is told the order is "not ready for handover", about a drink that was in fact
   handed over.

Please make both paths **idempotent on `Completed`**. When `UpdateOrderStatusAsync` returns `false`,
re-read the order:

- If it is already `Completed`, return `204` (the web: redirect as if it succeeded) and **skip the
  audit entry**, since nothing changed.
- A genuinely wrong state (`Pending`, `InProgress`, `Cancelled`) keeps the `400`, and so does an
  order that no longer exists, exactly as today.

Until this ships, the Flutter staff client shows the server's message verbatim, and its next queue
refresh removes the card.

### 8. Tests worth adding

- An omitted mode is inferred correctly, with and without a location.
- `Delivery` without a location is a `400`, including an unknown `LocationId` with blank text.
- Staff `/complete` on an already `Completed` order returns `204` with no audit entry.
- `/collected` loses a race to staff: it re-reads and returns `204`.
- An unknown value is a `400`.
- `/collected`: the happy path, not yours, not a pickup, not Ready yet, and a retry on an already
  `Completed` order returning `204`.
- The Ready notification text for each mode, including null.

## What the client will do

Nothing, until these fields appear in `docs/contracts/ApiContracts.cs` and `StaffContracts.cs`. The
client never sends or reads a field that is not in the contracts. Until then:

- Review keeps today's free-text location.
- The Ready wording is **neutral**, since both modes happen.
- There is no "I picked it up" button.

Once the contracts carry them, the client ships (the "pickup or delivery" phase of the redesign):

- A "How do you want it?" choice on Review. The location field shows only for delivery, and a
  missing one shows its error on the field, never a disabled button.
- The last choice and the last location are remembered on the device.
- Ready wording per mode.
- "I picked it up" on the caller's own Ready pickup order.
- A Pickup / "Deliver to …" badge on the staff queue and handover cards.
