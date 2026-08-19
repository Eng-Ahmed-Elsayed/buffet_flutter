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

## Not client-side

| Item | Status |
|---|---|
| **HTTPS** | ❌ Still absent. Re-tested this round: `https://digitalbuffet.runasp.net` does not respond. A 30-day bearer token travels in cleartext. **The one production blocker no client change can fix.** |
| Client-written Arabic stored as `?` | ❌ [backend-request-arabic-encoding.md](backend-request-arabic-encoding.md) |
| `drinkSourceOwnerName` empty when overdrawn | ❌ [backend-request-own-source-on-overdrawn.md](backend-request-own-source-on-overdrawn.md) |
| `/auth/login` ignores `Accept-Language` | ❌ Returns Arabic either way. |
| Two corrupt item images | ❌ `item-7` is a 64×64 brown placeholder; `item-2` is a truncated PNG that will not decode. The client falls back correctly for both. |
| iOS home-screen name | ⚠️ `.lproj` files written; needs one Xcode step on macOS — see [ios/Runner/README-localisation.md](../ios/Runner/README-localisation.md). |
