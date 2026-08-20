# §12 definition of done — verified status

Updated 2026-08-19 after eight audit rounds. **Verified** means exercised
against the running API or on a device, not merely present in source: the
audit found 23 defects, and several of the worst were invisible in code review.

Method: the R8-minified **release** APK installed on a Pixel 9 emulator, driven
against `http://digitalbuffet.runasp.net/api/v1` with all three test accounts.

| §12 item | Status | Evidence |
|---|---|---|
| Palette, radii, spacing, motion tokens — no ad-hoc values | ✅ | Grep-clean for `Color(0x`, literal durations, raw radii. Three literals found and tokenised in round one. |
| Both logo assets bundled; mark and lockup used | ✅ | Lockup on login, mark on splash/lock/settings, peak on the launcher icon. |
| RTL verified on every screen; no `left`/`right` | ✅ | Grep-clean. Every screen seen in **both** locales on device; layout mirrors correctly. |
| Quantity + unit bidi-isolated | ✅ | `Formatters.quantity`. Four separate isolation defects found and fixed; now covered by `test/shared/bidi_isolation_test.dart`. |
| Reduced motion honoured; targets ≥44px; text ≥4.5:1 | ✅ | `Motion.of` gate applied to tile selection and the shortage banner (it was dead code until round one). `Dimens.minTarget` enforced in the theme. |
| `mustChangePassword` cannot be skipped | ⚠️ **Untested** | Router guard and `PopScope` are in place and unit-tested, but **all three accounts return `false`** so the screen was never exercised live. |
| Token in secure storage; biometric gate with password fallback | ✅ | `flutter_secure_storage` only. Lock screen always offers "use password instead". |
| Biometric-changed clears the token | ✅ | Implemented in round three via a Keystore sentinel (`BiometricEnrolmentGuard`) — `local_auth` cannot report this on its own. Android only; iOS reports unavailable by design. |
| Idempotency key per composer session, reused on retry | ✅ | `201 duplicate:false` then `200 duplicate:true`, same order id. |
| "Usual order" one tap from the catalogue | ✅ | Card at the top of the composer; seen on device. |
| Sugar stepper allows explicit 0 | ✅ | Renders "بدون سكر"; zero is sent, not omitted. |
| Location accepts free text | ✅ | Autocomplete sends `locationId` or `locationText`. |
| Personal materials in violet; toggle only when relevant | ✅ | Verified on device: `Drink: سارة العتيبي's jar` in violet beside a neutral buffet chip. Selection was wrongly using violet until round one. |
| Declaration says "awaiting staff confirmation" | ✅ | Violet banner shown **before** committing, not only after. |
| Shortages warn, never block, never disable | ✅ | `/ready` returned `200` + warnings with a `-6` balance; no control disabled. |
| Order status compared by **name** | ✅ | `OrderStatus.fromWire`; ordinal comparison is unwritable by construction. |
| UTC timestamps converted | ✅ | `Formatters` converts; no raw UTC rendered. |
| `ApiError.message` surfaced as-is | ✅ | Seen live: the server's Arabic credential error on the login screen. |
| 401 clears the token and routes to login, centrally | ✅ | Single Dio interceptor; login is flagged to skip it. |
| No offline order queueing | ✅ | Failure keeps the composer filled with the same key; nothing is held. |
| Staff screens on the live `/staff/*` endpoints | ✅ | start, ready, deliverNow, complete and cancel all exercised end to end. |
| Declarations tab admin-only; staff never see a 403 control | ✅ | No declarations UI exists; the paths are absent from `ApiConfig` with a comment saying why. |
| Staff endpoints never driven via MVC | ✅ | JWT bearer only. |

## Parity work (2026-08-20)

From [backend-flutter-parity.md](backend-flutter-parity.md). The backend had already shipped
every field the client was blocked on — our `docs/contracts/` copy was four commits stale — so
§1, §2, §4 and §6 were all buildable and are now built. **§5 favourites is not implemented
server-side and was not attempted.**

| § | Item | Status | Evidence |
|---|---|---|---|
| 1 | Multiple drinks per order | ✅ | Draft-plus-list composer; one screen, no wizard. The single-drink path is unchanged — a lone drink in the draft is submitted without needing "add". |
| 1 | `maxLines` honoured, not hard-coded | ✅ | Read from `/catalogue`; `addLine` and `selectDrink` both refuse past it. Defaults to 25 so a stale server still bounds the client. |
| 1 | Buffet cap counted on the **resolved** source | ✅ | `resolvesToBuffet` is true when `drinkFromOwn == false` **or** `ownServingsLeft <= 0`, matching `BuildLine`'s silent fallback. Tested in both directions. |
| 1 | Cap enforced at the point of adding | ✅ | `addLine` refuses a draft that would break it, with the banner saying why. The **order button is never disabled** — the cap counts a stock reading. |
| 2 | Guest field gated on the privilege | ✅ | `canOrderForGuests` from `LoginResponse`, cached alongside the role so it survives a relaunch of a 30-day token. |
| 2 | Guest order lifts the cap — both halves required | ✅ | `capIsLifted` needs the privilege **and** a name; either alone leaves the cap in force, matching `EmployeeApi.cs:293`. |
| 3 | Pickers grouped «من موادي» / «من البوفيه» | ✅ | Owned first; a single flat grid when the user owns nothing. |
| 3 | An owned drink appears in **both** groups, once per jar | ✅ | Matches the web (`OrderViewModels.cs:98-116`). Partitioning would remove a real choice — someone saving their own beans still wants a coffee. |
| 3 | The tile carries the source; no "from my materials" toggle | ✅ | The group tapped *is* the answer, given before the drink is chosen rather than after. A toggle would be a second, quieter control contradicting the tile above it. |
| 3 | An owned item with nothing left still shows under «من موادي» | ✅ | Never hidden, never disabled — widget-tested at `ownServingsLeft == 0`. |
| 4 | Forced path hides the current password | ✅ | Calls `/auth/set-initial-password`; the voluntary path from settings still sends both. |
| 4 | Re-sign-in after `204` | ✅ | The token still claims `must_change_password`, so the client signs in again rather than patching local state. A failure is surfaced, not swallowed. |
| 6 | Extras filtered by the selected drink | ✅ | null = all, `[…]` = those, `[]` = row hidden. **Never conflated** — tested in all three states. |
| 6 | Disallowed extras cleared on drink change | ✅ | On `selectDrink` and on `applyUsual`, since an admin may have narrowed the list since the last order. |
| 8 | Double-portion warning on extras | ✅ | `VariantDto.ingredientItemIds` shipped after this was raised. The chip is marked and a hint appears under the row once such an extra is ticked. |
| 8 | The mark follows the **preparation**, not the drink | ✅ | Milk is in a فرنساوي and not a غامق; switching moves the mark and clears the hint. Unit- and widget-tested in both directions. |
| 8 | Annotate, never filter; warn, never block | ✅ | The chip stays selected and selectable, the extra is still sent, and the order button never goes off for it. An ingredient is part of the recipe and cannot be declined — that is what separates it from `allowedExtraItemIds`. |
| 7.5 | Declaring an item the buffet does not carry | ✅ | `POST /materials/declare-new` shipped after this was raised. «الصنف غير مدرج» reveals the new-item fields. |
| 7.5 | `quantity` is **packages** on the new-item path | ✅ | The label switches to «عدد العبوات» with the mode. Getting this wrong is silent — it would declare 2g of a 200g jar — so a test pins it. |
| 7.1 | Delivery location is plain text | ✅ | The suggestion list was dropped by request. Free text always sends `locationText`, which the server accepts for any place, so an unlisted spot still cannot block an order. |
| — | Back actually closes the app from a landing screen | ✅ | Was calling `Navigator.maybePop()`, which asks the very `PopScope` that refused it — the dialog appeared, "exit" did nothing. Now `SystemNavigator.pop()`, Android-only, with both paths tested. |
| — | The system navigation bar does not cover the order button | ✅ | Three-button navigation drew a ~48dp strip over "أرسل الطلب". The composer footer and both bottom sheets now add `MediaQuery.paddingOf` — `padding`, not `viewPadding`, which double-counts what the Scaffold already consumed. |
| 7.1 | "Usual" relabelled "آخر طلب" | ✅ | It is literally the last non-cancelled order; the old label overpromised a computed habit. |
| 5 | Saved favourites | ⛔ | Not built server-side — no table, no endpoints. Correctly absent from the client. |

Two defects found by review during this work, both mine, both fixed: a line silently dropped from
the request once the order hit `maxLines`, and a refetched catalogue publishing a lower cap
deleting drinks the user could still see on screen. Neither could have been caught by the
analyzer — the tests that now cover them were written after the review named them.

**Not verified against the running server.** The credential attempts needed to exercise these
paths live were blocked by the sandbox this session, so the above rests on the backend source in
`../buffet_app` (read directly) plus 218 passing tests — not on live calls. Worth re-running
against the deployment before release, particularly the `400` on a guest name from an
unprivileged caller.

## Not client-side

| Item | Status |
|---|---|
| **HTTPS** | ❌ Still absent. Re-tested this round: `https://digitalbuffet.runasp.net` does not respond. A 30-day bearer token travels in cleartext. **The one production blocker no client change can fix.** |
| Client-written Arabic stored as `?` | ❌ [backend-request-arabic-encoding.md](backend-request-arabic-encoding.md) |
| `drinkSourceOwnerName` empty when overdrawn | ❌ [backend-request-own-source-on-overdrawn.md](backend-request-own-source-on-overdrawn.md) |
| `/auth/login` ignores `Accept-Language` | ❌ Returns Arabic either way. |
| Two corrupt item images | ❌ `item-7` is a 64×64 brown placeholder; `item-2` is a truncated PNG that will not decode. The client falls back correctly for both. |
| iOS home-screen name | ⚠️ `.lproj` files written; needs one Xcode step on macOS — see [ios/Runner/README-localisation.md](../ios/Runner/README-localisation.md). |
