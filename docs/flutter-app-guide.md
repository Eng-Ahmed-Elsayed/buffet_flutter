# Digital Buffet — Flutter Client Reference

A build guide for the mobile client: **employee view and staff view only**. Admin work stays on
the web, where the import, reporting and audit screens already exist and are richer than a phone
should try to be.

This document is a specification, not a tutorial. It records what the backend actually does and
the decisions a developer would otherwise have to guess at. Every API shape below is taken from
`src/BuffetApp.Web/Api/ApiContracts.cs`, `EmployeeApi.cs` and `StaffContracts.cs`; every colour
from `src/BuffetApp.Web/wwwroot/css/site.css`.

---

## 0. Read this first: the whole API is live

Both halves of this app are served today. The employee endpoints have been on `/api/v1` since the
mobile API landed; the **staff endpoints shipped on 2026-08-18** as
`src/BuffetApp.Web/Api/StaffApi.cs`, covered by `tests/BuffetApp.Tests/StaffApiTests.cs`.

Build against a running server for both roles. [staff-api-spec.md](staff-api-spec.md) documents the
staff surface endpoint by endpoint, including four places where the implementation deliberately
differs from the original specification. **Three of those change what the app can render** — read
them before designing the staff screens:

| Deviation | What it means for the client |
|---|---|
| Declaration endpoints are **admin-only** | A staff token gets `403`. **Do not build a declarations tab into the staff view** — see §8.2 |
| `StaffOrderLineDto.SugarNameAr` is **always null** | The queue card shows the spoon count and source owner, never a sugar name |
| `GET /staff/queue` returns `Pending` + `InProgress` only | `Ready` orders are **not** in the default queue; pass `?status=Ready` for the handover list |

What you cannot do is reuse the *employee* endpoints for staff. A staff member's token works
everywhere, but every endpoint under `/api/v1` that is not `/staff/*` is scoped to the caller:

- `GET /orders/mine` filters on `RequesterUsername == caller` — it returns the staff member's
  *own* drinks, never the queue.
- `GET /orders/{id}` 404s on any order the caller did not place. That is deliberate (a 403 would
  confirm the order exists), and it means staff cannot open a queue item.
- `POST /orders/{id}/cancel` calls `CancelOwnAsync`, which is ownership-checked. It cannot cancel
  a queue order on a customer's behalf.

Those are correct for employees and were not loosened — the staff surface is additive. And do not
drive the MVC screens from the app: those actions are cookie-authenticated and antiforgery-
protected, and the API is bearer-only *precisely* so it never inherits ambient browser credentials.

The one rule that must survive the port: **stock is deducted at `Ready`, not `Completed`**, and
`OrderServingService` is the only path that may do it. `POST /staff/orders/{id}/ready` delegates to
it; there is a test asserting the endpoint writes ledger rows rather than stamping the status.

---

## 1. Designing the screens before writing code

Screens are designed and approved **before** any Dart is written. The route is Claude Code's
`/design` skill: it produces a canvas of artboards published as an Artifact, reviewed and adjusted
directly in the browser, and only then translated into widgets.

This replaces the Claude-design → export → Figma → Figma-MCP round trip that an earlier draft of
this document assumed. That path still works, but it loses the thing that matters most.

### 1.1 Why the round trip loses information

A design tool hands the coding agent geometry, hex values and layer names. It cannot hand over
*intent* — and most of the rules in this document are intent. A frame that is violet does not say
violet means "this came from someone's own jar"; a button that looks enabled does not say it must
**stay** enabled when stock runs short.

When the artboards are authored against §2 from the start, three failure modes never arise:

1. **Hardcoded hex instead of tokens.** An imported design gives literal colours, and a screen full
   of raw `Color(0xFF…)` cannot be themed and drifts from the web app on the first palette change.
2. **LTR-shaped layouts.** Design tools compose left-to-right by default. This app is Arabic-first;
   a layout reviewed only in LTR ships backwards.
3. **A dark theme invented independently.** If it is not derived from the palette, the accent stops
   clearing 3:1 on the dark ground and `accentBright` ends up carrying text at 2.72:1.

Whatever tool produces the visuals, this document stays authoritative for **meaning and
behaviour**; the design is authoritative for **layout and dimension**.

### 1.2 The five screens to design first

Login and first-run password change · the order composer with the sugar stepper, extras chips and
the "from my materials" toggle · order status through all four states · my materials with a
pending declaration · the staff queue card showing the source jar per line.

They are where every rule in this document becomes visible; the rest of the app is conventional and
can follow. Ask for the **states**, not just the happy path — a shortage warning that does not
disable, an order sitting in `Ready`, an empty catalogue, an expired token.

### 1.3 What not to design

- **A declarations tab in the staff view.** Those endpoints are admin-only; a staff token gets
  `403`. Confirming materials stays on the web (§8.2).
- **A sugar name on the queue card.** `SugarNameAr` is always null — design around the spoon count
  and the source owner.
- **A guest-order screen.** The API hard-codes `AllowMultipleBuffetDrinks = false` and reads
  `canOrderForGuests` from the token, not the body.
- **Any admin screen.** Import, reporting and audit stay on the web.

---

## 2. Identity

### 2.1 The logo

`src/BuffetApp.Web/wwwroot/images/` holds the two assets. Copy them into the Flutter project
rather than re-exporting or re-drawing:

| File | What it is | Use in the app |
|---|---|---|
| `logo-defi.png` | Full lockup: circuit mark + "DIGITAL EGYPT FOR INVESTMENT" wordmark | Login screen, about screen |
| `logo-defi-mark.png` | The mark alone | App bar, splash, notification icon |

The mark is a navy-to-violet circuit trace rising over a peak. **The palette is sampled from it** —
that is why `--brand` and `--accent` are the two ends of its gradient. Never recolour the logo to
match a theme; the theme already matches the logo.

The wordmark is Latin-only and reads left-to-right. In the RTL layout it stays LTR — wrap it in a
`Directionality(textDirection: TextDirection.ltr, …)` if it ever sits inside a row that flips, or
use the mark alone, which is direction-neutral and the safer default in app bars.

### 2.2 Colour

Ported verbatim from `site.css`. The comments are the contrast measurements — keep them, because
a palette edit is exactly when those silently stop holding.

```dart
// lib/theme/brand_colors.dart
abstract final class BrandColors {
  /// Logo gradient, deep-blue mid-stroke. 10.98:1 with white text.
  static const brand = Color(0xFF123A7A);
  /// The wordmark navy. 16.13:1 with white text.
  static const brandDark = Color(0xFF0B1E4B);
  /// Tinted from brand, not picked — keeps chips in one hue family.
  static const brandLight = Color(0xFFE9EFF9);
  /// The violet end of the gradient. A *fill*: 7.32:1 with white text.
  static const accent = Color(0xFF6D22D8);
  /// Lightened until it clears 3:1 on the navy bar. Non-text UI only —
  /// at 2.72:1 it must never carry white text.
  static const accentBright = Color(0xFFA78BFA);
  static const focus = Color(0xFF5417B0);
  static const ink = Color(0xFF141B2E);
  /// Holds AA on both white (5.67:1) and the page background (5.24:1).
  static const muted = Color(0xFF5C6780);
  static const surface = Color(0xFFFFFFFF);
  /// Neutral cooled toward the brand hue so cards read as white on it.
  static const page = Color(0xFFF4F6FA);
  static const danger = Color(0xFFB42318);
  static const warning = Color(0xFFB54708);
  /// Deliberately green, not brand-blue: "healthy stock" loses its meaning
  /// if the level colours are all one hue. 5.19:1 on white.
  static const ok = Color(0xFF0E7C5A);
}
```

Two rules carried over from the web, both easy to break in Flutter:

- **`accentBright` is non-text.** It marks position on the navy app bar. Putting a label on it
  fails AA at 2.72:1.
- **Violet means "mine".** Personal materials — an employee's own jar — are marked in `accent`
  throughout the web app. Do not reuse violet for a generic selection state, or "from my
  materials" stops being readable at a glance.

### 2.3 Shape, elevation, spacing, motion

```dart
// Radii
const radiusSm = 10.0, radius = 14.0, radiusLg = 18.0;

// Spacing — a 4px scale, named by role, so "gap between a heading and its
// section" is one decision made once.
const space1 = 4.0,  space2 = 8.0,  space3 = 12.0, space4 = 16.0;
const space5 = 24.0, space6 = 32.0, space7 = 48.0, space8 = 64.0;
```

Motion durations and curves, mapped from the CSS tokens. Duration expresses distance and
consequence; **exits are always faster than entrances**, because a thing leaving has already been
decided and waiting for it is pure cost.

| Token | Duration | Use |
|---|---|---|
| `instant` | 90ms | Colour-only feedback: hover, press-down |
| `fast` | 140ms | Acknowledgement: press, check, chip toggle |
| `base` | 220ms | Routine state change: panel, badge, row |
| `slow` | 320ms | Layout, overlay, route transition |
| `exit` | 140ms | Anything leaving |

```dart
/// Exponential ease-out: arrives at speed and settles. Reads as physical
/// without the dated overshoot of a bounce.
const easeOut = Cubic(0.16, 1, 0.3, 1);
/// Gentler, for small frequent moves where the above is too theatrical.
const easeSoft = Cubic(0.32, 0.72, 0, 1);
const easeInOut = Cubic(0.65, 0, 0.35, 1);
```

**Honour reduced motion.** The web collapses every duration to 1ms under
`prefers-reduced-motion`. Flutter exposes the same signal — gate durations on
`MediaQuery.disableAnimationsOf(context)` and return `Duration.zero`. Opacity and colour still
carry state; only spatial movement stops.

### 2.4 Typography and RTL

The app is **Arabic RTL first**. `MaterialApp` gets `locale: Locale('ar')`,
`supportedLocales: [Locale('ar'), Locale('en')]`, and the localisation delegates — Flutter then
flips the layout automatically. Do not hand-place widgets with `left`/`right`; use
`start`/`end` (`EdgeInsetsDirectional`, `AlignmentDirectional`) throughout, or the layout breaks
the moment someone switches to English.

The web deliberately uses system Arabic faces so it works offline with no CDN. Match that:
bundle **Cairo** or **Tajawal** as an asset font (both are open-licensed and cover Arabic well),
rather than fetching at runtime. `line-height: 1.7` on the web → `height: 1.7` in Flutter's
`TextStyle`; Arabic needs the extra leading and it is not the Material default.

Numbers in lists and tables use tabular figures — `fontFeatures: [FontFeature.tabularFigures()]`.

One bidi trap the web already hit and the app will too: **unit names are admin-entered data and
keep the language they were typed in**, so "جرام" regularly appears in an English screen and vice
versa. Left alone the bidi algorithm reorders the surrounding run and a quantity like
`988 جرام (1988 جرام)` renders visually scrambled. Isolate any widget that renders a
quantity-plus-unit — in Flutter, wrap the value in its own `Directionality` matching the page,
or compose it as a single `Text` with an embedded isolate character (`⁨ … ⁩`).

### 2.5 Touch targets and accessibility

Every interactive target is **at least 44px** (the web standard here; Material's 48dp default
satisfies it). All text clears **4.5:1**; focus indicators and non-text UI clear **3:1**. This is
already true of the palette above — it stays true only if new colour pairs are measured.

Label everything for screen readers with `Semantics`. Status is never colour alone: a `Ready`
order carries the word as well as the green.

---

## 3. Architecture

Follow the layered structure the Flutter team recommends — UI, logic, data — with a repository
seam. It is the same seam that kept this backend's move off Excel contained to one project.

```
lib/
  main.dart
  app/            MaterialApp, router, theme wiring
  theme/          brand_colors.dart, app_theme.dart, motion.dart
  data/
    api/          ApiClient (dio), endpoint methods, error mapping
    models/       DTOs mirroring ApiContracts.cs, json_serializable
    repositories/ AuthRepository, CatalogueRepository, OrderRepository,
                  MaterialsRepository, NotificationRepository, QueueRepository
    local/        SecureTokenStore, catalogue cache
  features/
    auth/         login, first-run password change, biometric unlock
    order/        catalogue browse, order composer, confirmation
    my_orders/    history and live status
    materials/    declare, my balances
    notifications/
    staff_queue/  STAFF ONLY — see §8
  shared/         widgets, formatters, result types
```

**State management:** Riverpod, or `provider` + `ChangeNotifier` if the team already knows it.
The choice matters less than the rule: **widgets never call the API directly.** They read from a
repository, so the offline cache and the token refresh live in one place.

**Serialisation:** `json_serializable` with `build_runner`. Hand-written `fromJson` on ~15 DTOs
drifts from the server the first time a field is added. Mirror `ApiContracts.cs` field-for-field
and keep the same names — the API is `camelCase` on the wire via System.Text.Json defaults.

**Routing:** `go_router`, with a redirect guard that implements the auth state machine in §5.

**Testing:** unit-test the repositories against recorded JSON; widget-test the order composer
(sugar stepper including explicit zero, the "from my materials" toggle appearing only when an
owned drink is selected); integration-test the login → order → status flow.

---

## 4. The API

Base URL `https://<host>/api/v1`. **JWT bearer only** — a cookie-authenticated request cannot
reach these endpoints, deliberately: the API has no antiforgery tokens, so accepting ambient
cookie credentials would hand it the CSRF exposure the MVC forms are protected against.

Send `Authorization: Bearer <token>` on everything except login. Send `Accept-Language: ar` (or
`en`) — **error messages are localised server-side from that header**, so the app should display
`ApiError.message` as-is rather than mapping codes to its own strings.

The OpenAPI document at `/openapi/v1.json` is **development-only**. Generate a client from it
against a dev instance if you like, but the contracts in `ApiContracts.cs` are the reference.

### 4.1 Endpoints available today (employee)

| Method | Path | Notes |
|---|---|---|
| `POST` | `/auth/login` | `{username, password}` → `LoginResponse`. Anonymous. |
| `POST` | `/auth/change-password` | `{currentPassword, newPassword}` → `204`. Min 8 chars. |
| `GET` | `/catalogue` | Drinks, sugars, extras, locations **and the usual order** in one round trip |
| `POST` | `/orders` | → `201 {orderId, duplicate:false}`, or `200 {duplicate:true}` |
| `GET` | `/orders/mine?take=` | Newest first. `take` capped at 100, defaults to 20 |
| `GET` | `/orders/{id}` | Caller's own only; **404** for anyone else's |
| `POST` | `/orders/{id}/cancel` | `204`. Pending only, ownership-checked |
| `GET` | `/notifications` | |
| `POST` | `/notifications/read` | |
| `GET` | `/materials/mine` | The caller's own balances, with a **relative** `imageUrl` |
| `POST` | `/materials/declare` | → **`202 Accepted`**, not `201` — see §7 |

`/catalogue` is bundled deliberately: a phone on office wifi should not need four requests to
draw one screen. Cache it, and refresh on app resume.

### 4.2 Login response

```jsonc
{
  "token": "eyJ…",
  "expiresUtc": "2026-09-15T08:00:00Z",
  "username": "someone@company.com",
  "displayName": "…",
  "role": "Employee",        // "Employee" | "Staff" | "Admin"
  "department": "…",
  "mustChangePassword": true // token works, but the account is on its seeded password
}
```

Tokens are signed HS256, `iss: BuffetApp`, `aud: BuffetApp.Mobile`, and last **30 days**
(`Jwt:ExpiryDays`). There is **no refresh-token endpoint** — when the token expires the user signs
in again. That is the flow biometric unlock in §5 is designed to make painless.

Claims on the token: `sub`, `jti`, name, `role`, `department`, `must_change_password`,
`can_order_for_guests`. Read the role from the login response, not by decoding the JWT client-side.

### 4.3 Order status

`Pending → InProgress → Ready → Completed`, plus `Cancelled`. Note the enum ordinals are *not*
in workflow order (`Ready = 4`) — **always send and compare the string name**, never the integer.

`Ready` means the drink was physically made; `Completed` means it was handed over. The app should
say so: `Ready` is the "come and collect it" moment and deserves the notification and the loudest
visual state, not `Completed`.

`OrderSummaryDto.isReady` is computed server-side; mirror it as a getter rather than a field.

### 4.4 Errors

Every failure returns `{"message": "…"}` — one shape to parse — with a real status code:
`400` validation and business-rule failures (message already localised), `401` bad credentials or
expired token, `404` not found *or not yours*, `500` a bug worth reporting.

Map `401` centrally in a Dio interceptor: clear the stored token and route to login. Do not retry.

---

## 5. Authentication flow

The state machine the router guard must implement:

```
        ┌──────────────┐
        │ cold start   │
        └──────┬───────┘
               ▼
      token in secure storage?
         │no            │yes
         ▼              ▼
      ┌───────┐   biometric enrolled?
      │ Login │      │yes        │no
      └───┬───┘      ▼           │
          │      ┌─────────┐     │
          │      │ Unlock  │     │
          │      └────┬────┘     │
          ▼           ▼          ▼
      mustChangePassword == true ?
         │yes                  │no
         ▼                     ▼
   ┌──────────────┐      ┌──────────┐
   │ Change pwd   │─────▶│   Home   │
   │ (no skip)    │      └──────────┘
   └──────────────┘         │
                    role == Staff ? queue : catalogue
```

Three rules:

1. **`mustChangePassword` is not dismissible.** The token works, so a careless client could skip
   the screen and order anyway. Block navigation until `204` comes back from
   `/auth/change-password`. Everyone starts on the shared seeded password (`DEFI@2026`) — until
   they change it, their account is not theirs.
2. **Role decides the landing screen**, from the login response. `Staff` → queue,
   `Employee` → catalogue. An `Admin` signing in should land on the catalogue with a quiet note
   that admin work is on the web; do not build admin screens.
3. **Never store the password.** Only the token goes to storage, and only in
   `flutter_secure_storage` (Keychain / Android Keystore) — never `SharedPreferences`.

### 5.1 Making first-time login easy

The friction is real: the username is a full email address and the seeded password is shared.

- **Default the email domain.** Show the field pre-filled with `@company.com` and let the user
  type only the local part, while still accepting a full address if pasted.
- **Keyboard and autofill:** `TextInputType.emailAddress`, `autofillHints: [AutofillHints.username]`
  and `[AutofillHints.password]`, wrapped in an `AutofillGroup` so the OS password manager offers
  to save the *new* password after the change screen.
- **Show-password toggle.** With a shared seeded password typed on a phone keyboard, hiding it
  helps nobody.
- **Remember the email** after a successful sign-in (plain preferences is fine — it is not a
  secret) so the second sign-in is password-only, and biometric-only after that.
- **One clear error.** The server returns the same message for a wrong password and a disabled
  account, so the endpoint cannot be used to discover which accounts exist. Do not try to be more
  specific in the client — you would be guessing.

### 5.2 Change password

Same screen serves the forced first-run case and the voluntary one from settings. Server rules:
current password must verify, new password **minimum 8 characters**. Validate the length locally
for instant feedback, but always surface the server's message on `400` — it is already in the
user's language.

Require a confirm field, and offer the reveal toggle. On success, if the user has biometrics
available, this is the natural moment to offer to enable them (§5).

---

## 6. Biometric authentication

Use `local_auth`. The honest framing matters: **biometrics unlock a stored token; they are not a
second factor.** The server knows nothing about the fingerprint. Design accordingly.

```dart
final auth = LocalAuthentication();
final canCheck = await auth.canCheckBiometrics;
final supported = await auth.isDeviceSupported();   // covers PIN/pattern fallback
final available = await auth.getAvailableBiometrics(); // face vs fingerprint, for the label
```

**Enrolment:** never enable it silently. Offer it once after a successful password sign-in — the
moment the token is fresh — and again in settings. Store a boolean "biometric enabled" flag
alongside the token.

**The gate:** on cold start with a stored token and the flag set, call `authenticate()` before
revealing any screen. `flutter_secure_storage` on Android should be configured with
`encryptedSharedPreferences: true`; on iOS the Keychain accessibility should be
`first_unlock_this_device`, so the token never syncs to another device via iCloud Keychain.

```dart
final ok = await auth.authenticate(
  localizedReason: 'تأكيد هويتك للدخول إلى البوفيه الرقمي',
  options: const AuthenticationOptions(
    biometricOnly: false,   // allow device PIN — a wet finger must not lock someone out
    stickyAuth: true,       // survive the app being backgrounded mid-prompt
  ),
);
```

Four failure modes to handle explicitly, because each one strands a user otherwise:

- **Cancelled / failed:** stay on the lock screen with a "use password instead" button that
  clears the token and routes to login. There must always be a way past.
- **No biometrics enrolled on the device** (`notEnrolled`), or hardware unavailable: fall back to
  password sign-in silently and turn the flag off.
- **Biometrics changed** (a new fingerprint added): treat as untrusted — clear the token and
  require a full password sign-in. This is the one case where being strict is right.
- **Token expired anyway:** the biometric gate passing does not make a 30-day-old token valid.
  The first `401` still routes to login.

**Never** gate on biometrics without a stored token — there is nothing to unlock, and prompting
for a fingerprint on a login screen teaches users the prompt is meaningless.

---

## 7. The employee view

### 7.1 Ordering — one screen

The web deliberately puts ordering on a single screen. Match it; a wizard on a phone for a cup of
coffee is worse, not better.

- **Tappable drink tiles**, image from `CatalogueItemDto.imageUrl` (relative — resolve against the
  API host), falling back to a category emoji when null. Images are uploaded by admins and served
  from `/uploads/items/`; treat a 404 as "use the fallback", since the uploads folder is not
  covered by database backups.
- **Sugar stepper where 0 is valid and explicit.** Not a blank field — "no sugar" is a choice the
  user makes, and the server distinguishes it from "unspecified". Sugar must be named explicitly
  on the order; the service only auto-resolves it when exactly one active sugar exists.
- **Extras as chips**, multi-select.
- **"الطلب المعتاد" — the usual order.** `/catalogue` returns `usual` with a human-readable
  `summary` and the full `lines`, *including which jar each component came from*. One tap fills
  the composer. This is the single highest-value feature in the app; put it at the top.
- **Delivery location is a combo, not a dropdown.** The managed list is a *suggestion*: an
  unlisted place must never block an order. Use an autocomplete that sends `locationId` when a
  suggestion is picked and `locationText` when the user types their own.

**Personal materials in the composer.** Items the employee owns are marked in violet with the
servings remaining (`hasOwnStock`, `ownServingsLeft`). The "from my materials" toggle appears
**only once such a drink is selected** — showing it always is noise for the majority who own
nothing. It maps to `drinkFromOwn` / `sugarFromOwn` / `ownExtraItemIds` per line.

**Shortages warn but never block** — including for personal stock. If someone's own jar has run
out, the order still goes through and staff see the warning. Never disable the order button on a
stock reading; physical and recorded stock drift, and halting service is worse than a negative
number an admin reconciles later.

**Guest orders are off in the mobile client.** The server hard-codes
`AllowMultipleBuffetDrinks = false` for API orders and reads `canOrderForGuests` from the token,
not the request body — the client cannot grant itself the permission. Do not build a guest screen
without a matching backend change.

### 7.2 Idempotency — do not skip this

`PlaceOrderApiRequest.idempotencyKey` is client-generated. **Generate a UUID when the composer
opens, keep it across retries, and only discard it once the order is confirmed.** A dropped
response on office wifi otherwise becomes a second coffee.

The server distinguishes the cases for you: `201` with `duplicate: false` means created; `200`
with `duplicate: true` means your retry matched an existing order. Both are success — show the
same confirmation.

### 7.3 Tracking

Poll `GET /orders/{id}` while an order is live; there are no push notifications or websockets
today. Poll on a **timer of ~15s while the screen is foregrounded**, stop on background, and
refresh once on resume. Do not poll a completed or cancelled order.

Cancellation is **pending-only** and ownership-checked. Hide the cancel action once the status
leaves `Pending` rather than showing a button that will 400.

### 7.4 Notifications

`GET /notifications` and `POST /notifications/read`. Kinds: `OrderReady`, `DeclarationConfirmed`,
`DeclarationRejected`, among others. In-app only — **there is no SMTP and no push** in this
system, a deliberate decision. Poll on resume and show an unread badge; do not promise the user a
notification that arrives while the app is closed.

### 7.5 My materials

`GET /materials/mine` returns quantity, `servingsLeft` and a `level` string for the colour band,
plus `imageUrl` — the item's picture, so a jar shown as a photograph in the composer is not a
generic glyph one screen later.

**`imageUrl` here is root-relative** (`/uploads/items/12.png`), unlike `CatalogueItemDto.imageUrl`
on `/catalogue`, which is absolute. Resolve this one against the configured API host, so switching
a build from staging to production needs no host-stripping. It is `null` whenever no image was
uploaded — the normal case — and a `404` on the file is not an error either: §7.1 notes the
uploads folder is outside database backups, so a row can outlive its file. Both cases fall back to
the category glyph without surfacing anything to the user.

`POST /materials/declare` returns **`202 Accepted`, not `201`** — and the wording of the
confirmation must reflect that:

> **Employee declares, staff confirms.** Stock only exists once staff confirm the jar physically
> arrived. A declaration alone creates nothing.

Say "تم إرسال الإقرار — بانتظار تأكيد الموظف", never "تمت الإضافة". The user will otherwise
believe they have stock they do not have, and the first order that draws on it will surprise them.

---

## 8. The staff view

These endpoints are **live**, in `src/BuffetApp.Web/Api/StaffApi.cs`. Model the DTOs from
`src/BuffetApp.Web/Api/StaffContracts.cs` and build against a running server.

Note the declaration endpoints are **admin-only** — a `Staff` token gets `403` on all three. See
the callout in §0.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/staff/queue` | `Pending` + `InProgress` only, oldest first. `?status=Ready` for handovers, `?take=` caps at 200 |
| `GET` | `/staff/orders/{id}` | Full detail, **any** order — no ownership filter |
| `POST` | `/staff/orders/{id}/start` | → `InProgress` |
| `POST` | `/staff/orders/{id}/ready` | → `Ready`; `?deliverNow=` also completes |
| `POST` | `/staff/orders/{id}/complete` | → `Completed` |
| `POST` | `/staff/orders/{id}/cancel` | With a reason; reverses and re-books as waste |
| `GET` | `/staff/declarations` | Pending personal-material declarations. **Admin only** |
| `POST` | `/staff/declarations/{id}/confirm` | Confirm receipt — **this is what creates stock**. Admin only |
| `POST` | `/staff/declarations/{id}/reject` | With a reason. Admin only |

Constraints the backend holds, and the app must not work around:

1. **`/ready` is the only thing that deducts stock**, via `OrderServingService` — the one path that
   knows whose jar each component comes from. There is a test asserting the endpoint writes ledger
   rows rather than stamping the status.
2. **Cancelling a `Ready` order reverses the consumption and re-books it as waste** — the balance is
   unchanged but nobody is credited with a drink they never received.
3. **Every line names its source owner.** `StaffOrderLineDto.DrinkSourceOwnerName` is the empty
   string for company stock, otherwise the owner's display name. That is what tells the person
   making the drink which jar to reach for, and it is why staff get their own DTO rather than the
   employee's `OrderLineDto` (whose `drinkFromOwn` booleans are computed relative to the caller).
4. **Shortages come back as `200` with a `warnings` array**, never `400`. `ServeResultDto.Warnings`
   carries item, owner, shortfall and unit. An empty array is the normal case; a populated one is
   still success.

### 8.1 Building the queue screen

- **The queue is the home screen** for `role == "Staff"`. Oldest first — it is a work queue, not a
  feed. Group by status, `Pending` at the top.
- **Poll every ~10s foregrounded**, pause on background. Staff keep the screen open; a stale queue
  is worse than a slightly chatty one.
- **Each card shows** requester and department, delivery location, drinks with the spoon count and
  extras, the per-line note, `waitingSeconds` as an ageing indicator, and — prominently — **which
  jar each component comes from**, in violet when it is someone's personal stock. There is no sugar
  *name* to show: `sugarNameAr` is always null.
- **Actions are one tap with an undo window**, not a confirm dialog. Staff hands are busy. The
  exception is **Cancel**, which takes a reason and genuinely warrants the dialog.
- **`Ready` is the important button.** Make it the largest target on the card. `deliverNow` (ready
  and handed over in one motion) is the common case at the counter — offer it as the primary
  action with plain `Ready` secondary.
- **Never disable an action on a stock shortage.** `/ready` returns `200` with a `warnings` array —
  surface it on the card after serving; do not treat it as a failure.
- **Handovers need a second list.** The default queue is `Pending` + `InProgress` only, so an order
  marked `Ready` disappears from it. Fetch `?status=Ready` for the "waiting to be collected" list —
  unless you used `deliverNow`, which serves and completes in one call and never enters that state.
- **No declarations tab.** Those endpoints are admin-only (§8.2).

---

### 8.2 Declarations are admin-only

`GET/POST /staff/declarations*` sit in a nested group with `AdminOnly`, tighter than the
`StaffOrAdmin` policy around them. **A staff token gets `403` on all three.**

The reason is separation of duties: confirming a handover creates stock out of nothing but
somebody's word, and the person who takes the jar should not also be the only person who signs for
it. The web screens narrowed to admin for the same reason, and mapping these as staff would have
re-opened through the API exactly what was closed on the web.

For the client this means: **no declarations tab in the staff view.** An employee declares in the
app (§7.5, `202 Accepted`) and an admin confirms on the web. If a staff screen ever needs to show
that a confirmation is pending, it can only do so for the signed-in user's own materials.

## 9. Offline and resilience

Office wifi drops. Assumptions worth building in:

- **Cache the catalogue** with its timestamp; render from cache instantly on launch and refresh in
  the background. It changes rarely.
- **Cache the last `/orders/mine` page** so history renders offline, clearly marked as of its
  fetch time.
- **Never queue orders offline.** It is tempting and it is wrong: the order would be placed
  minutes later against stock that has moved, and the user would have walked to the counter
  expecting a drink nobody is making. Fail the placement, keep the composer filled, and let them
  retry with the same idempotency key.
- **Timeouts:** 10s connect, 20s receive. The database round trip to a hosted endpoint is ~100ms
  and a screen may issue several.
- **Retry only idempotent GETs**, with backoff. `POST /orders` is safe to retry *only* because of
  the idempotency key — and only with the same key.

---

## 10. Packages

| Concern | Package | Note |
|---|---|---|
| HTTP | `dio` | Interceptors for bearer, `Accept-Language`, 401 handling |
| Secure storage | `flutter_secure_storage` | Keychain / Keystore. **Not** `SharedPreferences` |
| Biometrics | `local_auth` | Plus platform setup in §11 |
| State | `flutter_riverpod` | Or `provider` if the team knows it |
| Routing | `go_router` | Redirect guard implements §4 |
| Serialisation | `json_serializable` + `build_runner` | Mirror `ApiContracts.cs` |
| Localisation | `flutter_localizations` + `intl` | `generate: true` in `pubspec.yaml` |
| Dates | `intl` | `ar` locale; **the server sends UTC — convert for display** |

On dates: every timestamp in the API is UTC (`createdAtUtc`, `readyAtUtc`, `expiresUtc`). The
server reports in `Arab Standard Time`. Parse as UTC and convert to local for display; never
render a raw UTC value.

---

## 11. Platform setup

**Android** — `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
```
`MainActivity` must extend `FlutterFragmentActivity` (not `FlutterActivity`) or `local_auth`'s
prompt crashes. `minSdkVersion 23`. Enable `encryptedSharedPreferences: true` on
`flutter_secure_storage`.

**iOS** — `Info.plist`:
```xml
<key>NSFaceIDUsageDescription</key>
<string>لاستخدام بصمة الوجه لتسجيل الدخول السريع إلى البوفيه الرقمي</string>
```
Set Keychain accessibility to `first_unlock_this_device` so the token does not sync via iCloud.

**Both** — if the API is served over plain HTTP in development, that needs an explicit ATS
exception (iOS) and a network-security config (Android). **Production must be HTTPS**; do not ship
the exception.

---

## 12. Definition of done

- [ ] Palette, radii, spacing and motion tokens ported and used — no ad-hoc hex values
- [ ] Both logo assets bundled; mark used in the app bar, lockup on login
- [ ] RTL verified on every screen; no `left`/`right`, only `start`/`end`
- [ ] Quantity + unit strings bidi-isolated
- [ ] Reduced-motion honoured; all targets ≥ 44px; text ≥ 4.5:1
- [ ] `mustChangePassword` cannot be skipped
- [ ] Token in secure storage only; biometric gate with a working password fallback
- [ ] Biometric-changed clears the token
- [ ] Idempotency key generated per composer session and reused on retry
- [ ] "Usual order" is one tap from the catalogue screen
- [ ] Sugar stepper allows explicit 0
- [ ] Location accepts free text
- [ ] Personal materials in violet; toggle appears only when relevant
- [ ] Declaration confirmation says "awaiting staff confirmation"
- [ ] Shortages warn, never block, never disable a button
- [ ] Order status compared by **name**, never ordinal
- [ ] UTC timestamps converted for display
- [ ] `ApiError.message` surfaced as-is (already localised)
- [ ] 401 clears the token and routes to login, centrally
- [ ] No offline order queueing
- [ ] Staff screens built against the live `/api/v1/staff/*` endpoints
- [ ] Declarations tab shown to admins only; staff never see a control that returns 403
- [ ] Staff endpoints never driven via the MVC screens

---

## References

| What | Where |
|---|---|
| Wire contracts | `src/BuffetApp.Web/Api/ApiContracts.cs` |
| Endpoint behaviour | `src/BuffetApp.Web/Api/EmployeeApi.cs` |
| Staff actions to port | `src/BuffetApp.Web/Controllers/StaffController.cs` |
| Staff wire contracts | `src/BuffetApp.Web/Api/StaffContracts.cs` |
| Staff endpoint behaviour | `src/BuffetApp.Web/Api/StaffApi.cs` |
| Why the staff API is shaped as it is | [staff-api-spec.md](staff-api-spec.md) |
| Palette and motion tokens | `src/BuffetApp.Web/wwwroot/css/site.css` |
| Logo assets | `src/BuffetApp.Web/wwwroot/images/` |
| Roles and statuses | `src/BuffetApp.Core/Enums/` |
| Token shape and lifetime | `src/BuffetApp.Web/Security/JwtTokenService.cs` |
| Domain rules | `README.md` § Key design decisions |
