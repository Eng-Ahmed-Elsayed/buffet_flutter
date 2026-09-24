# Figma redesign: decisions and mapping

**Status:** decided 2026-09-24; being built on `feat/figma-redesign`.
**Source:** Figma file `bKHrXIl431VsFoghgKyDBu` ("DEFI - Kitchen app"), Design and Components pages.
**Exports:** `design/figma/` (**not added yet**), one PNG per frame at 2x, exported by hand (see
*Access*).

This document records what we took from the Figma design, what we remapped onto the business, and
what we dropped, with the reason for each. It sits beside
[flutter-app-guide.md](flutter-app-guide.md) and does not replace it:

- **The guide is authoritative for meaning and behaviour.** Stock warns but never blocks, violet
  means "my own jar", status is compared by name, and so on.
- **Figma is authoritative for layout, dimension and visual language.**
- **This file decides the places where the two disagree.**

## Access

The design account is a **View seat on a Professional plan**. Figma caps that seat at about
6 MCP calls a month, and the first session used them all. So the MCP is not the working channel for
this design. The frames are exported as PNGs into `design/figma/`, and colours are sampled from
those. Font names are read off the Figma UI by hand. A Dev or Full seat would restore the MCP.

## What the design covers, and what it does not

**Designed:** 8 frames, 390dp, **English/LTR only, light only, happy path only**:
Splash · Onboarding · Login · Home · Drink Details · Order Summary · Tracking · Settings.
The Components page adds the logo, a card, add/subtract buttons and two 4-state stepper chips.

**Not designed:** Arabic/RTL (the primary locale) · lock screen · forced change-password · my
materials and the declare sheet · favourites list · notifications · empty / loading / error /
expired-session states · shortage warning · guest mode · cancel and the Cancelled state · **the
whole staff view**.

How these get designed is **still open** (see *Open*). CLAUDE.md's "design before Dart" says they
should be designed and approved before any widget is written.

## Decisions

| # | Question | Decision |
|---|---|---|
| D1 | How to read the design | PNG exports in `design/figma/`; font names read by hand |
| D2 | Order flow | **(Choose a drink →) Drink Details → Review → Place.** No cart left on Home. See *Ordering* |
| D3 | Onboarding | **First-launch explainer**: the designed layout, shown once per install, skippable, with copy that explains the service instead of the coffee slogans, and no AI-generated stock photos |
| D4 | Employee navigation | **Bottom nav: Home · Orders · Materials · Account.** Staff are unchanged: they land on `/queue`, with no bottom nav |
| D5 | Pickup or delivery | **Both happen**, so the **client's** Ready wording **changes to neutral** ("Your order is ready"). It never says "on its way" or "come and collect it". **This is a change:** today's client copy and guide §4.3 say "collect" (see *Rules this redesign changes*). The server writes its own Ready text, used as the notification row and the push body (`NotificationService.cs:29`): «طلبك رقم N جاهز للاستلام». «للاستلام» means "ready to be received", which is true whether the drink is collected or delivered, so it is left alone and needs no backend request |
| D6 | Fonts | **The Figma Latin font for English, Cairo for Arabic.** The Latin family is **not confirmed yet**; the screenshots suggest Inter. Bundled as an asset only if its licence allows (Inter is OFL). English UI uses Cairo as the fallback, so Arabic item names still render correctly |
| D7 | Backend requests | Drink description and menu group ([request](backend-request-drink-description-and-group.md)); `StartedAtUtc` ([request](backend-request-order-started-at.md)). A pickup/delivery field was **not** requested: neutral wording (D5) covers it |
| D8 | Branch | `feat/figma-redesign`, one commit per phase, never pushed |

## Visual language

**Palette:** sampled from the Figma screenshots, to be confirmed against the 2x exports.

| Role | Value | Contrast | Note |
|---|---|---|---|
| Primary: filled buttons, headings, active states | `#1C4C9F` | 8.13 on white, 7.08 on page | from Figma |
| Page background | `#E7F0FF` | — | from Figma. Every existing semantic colour still passes on it: ok 4.52, warning 4.73, danger 5.73, violet 6.38, muted 4.94 |
| Icon blue: icons, inactive page dot | `#2A71F0` | 3.88 on page | **non-text only** |
| Link text | `#1563EE` | 4.52 on page, 5.18 on white | Figma's `#2A71F0` fails AA as text (3.88), so darkened, same hue |
| Input and outline-button border | `#6B8AC1` | 3.04 on page, 3.48 on white | Figma's `#8DA5CF` fails the 3:1 non-text minimum (2.18), so darkened, same hue |
| Violet `accent` | `#6D22D8` | unchanged | **still means "from my own jar" and nothing else.** Figma uses no violet in the UI, so nothing collides |
| danger / warning / ok | unchanged | see above | Figma has no semantic colours; ours are kept |

**Shape:** pill-shaped primary and outline buttons (55dp in Figma), rounded white cards on the
pale-blue page, circular icon buttons. Radii and spacing are taken from the exports and go into
`lib/theme/dimens.dart`. The 4px spacing scale is kept unless the design contradicts it.

**Chrome:** a light top bar (logo, bell with unread badge, initials avatar) replaces the navy bar.
`accentBright` existed to mark position on the navy bar and becomes unused. It is removed rather
than repurposed.

## Screen mapping

✅ taken · 🔁 taken, remapped to our data · ❌ dropped · ➕ added (missing from the design)

### Splash ✅
The pale gradient and centred logo lockup.

### Onboarding 🔁 (D3)
The layout is kept (hero card, dots, Next / Sign in, Skip). The three slides explain the service:
order from where you are; staff prepare it and you are told when it is ready; bring your own
materials and draw on them. Shown once per install. Skip and Sign in both go to login.

### Login ✅ layout
- ❌ **Register** (primary button and footer link). Admins create accounts; there is no sign-up.
  The primary button is **Sign in**.
- ❌ **Forgot?** as a reset flow. There is no endpoint, and deliberately no SMTP. It becomes a sheet
  that says to ask the buffet admin to reset the password.
- 🔁 **Use Biometric** moves to the **lock screen**, restyled into the same layout. Biometrics
  unlock a *stored* token, and there is none at login.
- ➕ The language switch, which must stay on login (see CLAUDE.md).

### Home 🔁
| Figma | Ours |
|---|---|
| Logo · bell · settings · avatar | Logo · bell (unread badge) · initials avatar. No settings icon, because the Account tab covers it: one destination, one control |
| "Good Morning, Salma" | ✅ time-of-day greeting with `displayName` |
| Tagline "Boost your metabolism…" | ❌ a health claim with no data behind it |
| Search | ✅ client-side over `/catalogue`, matching `nameAr` and `nameEn` |
| Category chips | 🔁 Filters over the menu. The menu itself **keeps guide §7.1's source sections in every case: «من موادي» first** (violet, only when the user owns something), **then «من البوفيه»** (neutral). The chips are the menu groups once the backend ships them, with drinks that have no group under «أخرى» / "Other"; they filter within both sections. Until then, the chips are the two source sections themselves, as jump links |
| "Popular" cards | 🔁 **Favourites.** Each card shows a sugar count, so it is a saved order. The existing strip rules still hold (4 most recent, "See all" only when `/favourites` exists, retired items marked) |
| "Recommended for you" | 🔁 **the full menu**: image, name, description (once shipped) |
| "OUT OF STOCK" badge | 🔁 `inStock == false` shows a **warning badge and the row stays tappable**. Shortages never block |
| — | ➕ outstanding-order card (above everything while an order is live) · ➕ guest order entry (when `canOrderForGuests`) |

### Drink Details 🔁
| Figma | Ours |
|---|---|
| Hero image, title | ✅ `imageUrl`, with the `ItemImage` fallback glyph |
| ★ rating | ❌ no ratings exist |
| Description | ✅ once the backend ships it; otherwise omitted |
| "Choose size" S/M/L | 🔁 **Preparation** (`variants`), shown only when there is more than one |
| Extras chips | ✅ filtered by `allowedExtraItemIds`, with the double-portion mark kept |
| Sugar chip-stepper **and** sugar slider | 🔁 **one** stepper; 0 is an explicit "no sugar". A slider cannot make zero a stated choice |
| "Mint leaves" slider | ❌ an extra is one fixed serving; there is no amount |
| — | ➕ source choice, only when `hasOwnStock`: «من موادي» in **violet**, «من البوفيه» **neutral**. Violet never marks the buffet |
| Quantity stepper | 🔁 shown **only when this drink has room for more than one line**. The room is whatever the controller already computes; nothing is hard-coded. There is no per-line quantity, so the stepper adds identical lines. The two caps: <br>• `maxLines` applies to every line. <br>• The buffet cap applies to every line that **resolves** to buffet stock (`drinkFromOwn == false`, or `ownServingsLeft <= 0`). It is `maxBuffetDrinks`, or `maxLines` when `capIsLifted`. <br>At the cap it states why and does not silently stop |
| "Add to Orders" | 🔁 **Continue** → Review |

### Review order (Figma "Order Summary") 🔁
- ✅ Lines with thumbnails, the location card, notes, **Place order**.
- ❌ Payment, promo code and price breakdown. They are already hidden in the Figma frame, and there
  is no money in this system.
- ➕ Removable lines; "Add another drink" while `lines < maxLines` (it returns to **Choose a
  drink**; the buffet cap is enforced when the line is added, as today); save-as-favourite; the
  guest's name, shown as a statement. It was entered first, on Choose a drink (see *Ordering*).
- A favourite tap seeds the flow and lands **directly on Review**.

### Tracking 🔁
- Figma has 5 steps; we have 4 statuses. "Kitchen takes order" and "Preparing" are both
  `InProgress`, so the timeline is **Sent → Being prepared → Ready → Completed**.
- `Ready` is the loudest state and is never shown by colour alone.
- ❌ "Receipt Order": no money.
- ➕ Cancelled state, Cancel (Pending only), Order again.
- The line summary follows the Figma pattern: preparation · N spoons · extras.

### Account (Figma "Settings") 🔁
- ✅ Name, Logout, Version.
- 🔁 "Member since" becomes **department**, which we have.
- ❌ Order History (duplicates the Orders tab), Payment Methods, Notifications (the bell already
  reaches it), Help Center (no content), Share.
- ➕ Language, biometric toggle, change password, and the admin-on-web note.

## Ordering (D2)

The composer is split into three pushed screens sharing one `ComposerController`, whose lifetime is
the flow:

1. **Choose a drink.** Search, the favourites strip and the menu list: the same widgets as Home.
   - It is where the flow starts for **staff** (the queue's "order for myself"), for **guest mode**
     (Home's guest entry), and for **"Add another drink"**.
   - In guest mode the **guest name is its first field**. That preserves "guest mode asks for the
     name first", and it means `capIsLifted` already holds by the time a quantity stepper is shown.
     **Every way off this screen runs the name check**: a menu-row tap and a favourite tap (which
     would otherwise jump straight to Review, where the name has no field). With no name, the
     handler reveals the error on the field and stays put. Nothing is disabled.
   - Employees ordering for themselves skip this screen: tapping a menu row on Home opens Drink
     Details directly.
2. **Drink Details** edits the current line.
3. **Review** holds all the lines, plus location, notes, save-as-favourite and Place order.

Everything the controller guarantees today still holds, and its tests are unchanged:

- The idempotency key is minted when the flow opens, kept across retries, and discarded only on
  confirmation.
- `setMode` never mints a key.
- `mode` and the favourite fields stay in both `ComposerState` constructor calls.
- The buffet cap is enforced when a line is added.
- Place order is never disabled. The guest name gates it by revealing the error on the field.
  Leaving Choose a drink in guest mode is gated the same way (above).

Guide §7.1 ("ordering — one screen") **will be** updated to describe the steps in the phase that
builds them (Phase 5).

## Rules this redesign changes (CLAUDE.md is updated as each lands)

| Old rule | New rule |
|---|---|
| The employee landing screen is the home hub with a permission-aware action grid | The landing screen is the **Home tab** of a bottom-nav shell: outstanding order, favourites, menu |
| `home_screen_test`: "New order" reachable without scrolling at 320dp | The outstanding order (when live) and the first menu row are reachable without scrolling at 320dp |
| Notifications and settings live in the home app bar only | The bell lives in the top bar; settings lives in the Account tab. Still one control per destination |
| Ordering is one screen (guide §7.1) | Ordering is (Choose a drink →) Drink Details → Review |
| The favourites strip lives on the composer as well as the hub, because staff never see the hub | It lives on **Choose a drink** as well as Home, for the same reason |
| Guest mode asks for the name first | Unchanged in substance: the name is the first field of Choose a drink |
| Ready is the "come and collect it" moment (guide §4.3; `readyBody`, `outstandingReadyBody`, `alertReadyBody`, `channelReadyDescription`, `handoverTab`, `noHandoversBody` in the ARB files) | Ready is still the loudest state, but the wording is neutral (D5). Reworded in Phase 6. Android should update an existing channel's *description* when the channel is re-created with the same id, which the `@channelReadyName` note ("frozen") does not cover; **verify on a device** |
| Theme tokens are ported verbatim from the web's `site.css` (CLAUDE.md, guide §2.2) | Tokens come from Figma, fixed for contrast. **The app and the web app now differ in palette** unless the web is restyled too |
| Design before Dart | Still the rule. How the screens Figma does not cover get designed is open (see *Open*) |

## Open

- **Design for the screens Figma does not cover** (the list at the top). Either the designer adds
  them to Figma (and the Arabic/RTL versions), or they are drafted here as a design canvas and
  approved before any Dart is written. Building first and reviewing screenshots afterwards would
  break "design before Dart", so it is not the default.
- **The Latin font family** and the exact colours, from the exports.
