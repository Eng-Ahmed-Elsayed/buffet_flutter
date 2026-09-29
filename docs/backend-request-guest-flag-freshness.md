# Backend request: a revoked guest privilege should take effect before the token expires

**Repo:** `../buffet_app` (ASP.NET Core 10)
**Status: DONE in the backend repo 2026-09-28, both parts** (`GuestPrivilege.cs`, `EmployeeApi.cs`,
`OrdersController.cs`, `Program.cs`; three tests in `EmployeeApiParityTests`). The contract is
synced into `docs/contracts/`, and **the client reads the catalogue's value** since the same day
(`guestPrivilegeProvider`). **Not yet deployed or verified live**: the backend change was still
uncommitted at sync time. Until it deploys, the live catalogue has no field and the client falls
back to the sign-in value, as before.
**Left open by the backend:** the web still draws its guest link from the cookie
(`_Layout.cshtml:79`, `_OrderFormFields.cshtml:88`), so a revoked user sees the link and is refused
when following it.
**Severity:** medium. An admin who switches the privilege off sees it still work for up to 30
days. The web and the app both honour it until then.

---

## What was reported

"The *order for a guest* button shows whether the user has the flag or not."

## What the code does (read, not exercised live)

The client is correct as of sign-in. Home draws the button only when
`canOrderForGuestsProvider` is true. That value is `LoginResponse.canOrderForGuests`, cached in
secure storage so a relaunch keeps it (`lib/features/auth/auth_controller.dart`,
`lib/data/local/preferences_store.dart`). The login endpoint fills it from the user row
(`EmployeeApi.cs:81`).

The problem is when it is read. **The privilege travels as a claim in the 30-day token**
(`can_order_for_guests`), and nothing re-reads it:

- `POST /orders` passes `principal.CanOrderForGuests()` straight from the claim
  (`EmployeeApi.cs:307`, `:319`). `OrderService.PlaceAsync` checks that value
  (`OrderService.cs:230`), so **a revoked user can still place guest orders**, with the buffet
  cap lifted, until they sign in again.
- `OrdersController.cs:44/53/68` (the web) authorise with the same claim, so the web has the same
  gap.
- No endpoint returns the current value, so the app has no way to learn it without a new sign-in.

`/auth/set-initial-password` already solves the same problem for `MustChangePassword`: it
re-reads the row instead of trusting the claim (`EmployeeApi.cs:115`).

## Requested change

1. **Re-check the stored row on `POST /orders`** (and on the web controller) when a guest name is
   present, as set-initial-password does. That is the fix for the privilege itself, and it needs
   no client change: a revoked user gets the existing `GuestOrderNotAllowed` refusal, and the app
   shows its message as-is.
2. **Publish the current value on `GET /catalogue`**: `bool CanOrderForGuests` on
   `CatalogueResponse`, read from the user row. Home fetches the catalogue on every load and
   resume, so the button would follow a change within one refresh. The change is additive.

## What the client does

`guestPrivilegeProvider` (`lib/features/order/composer_screen.dart`) takes
`CatalogueResponse.canOrderForGuests` when the catalogue has it, and the cached sign-in value when
the catalogue is loading, failed, or came from a server that predates the field. Home's guest
button and the composer's guest mode both read it, so an admin's change shows on the next catalogue
fetch. Home refetches the catalogue on resume and on pull-to-refresh (it stays mounted beneath
every tab, so resume is what carries a change made while the app was away; before 2026-09-29 it
reloaded only on pull-to-refresh). `home_screen_test.dart` and `composer_screen_test.dart` pin both
directions, and the resume path.
