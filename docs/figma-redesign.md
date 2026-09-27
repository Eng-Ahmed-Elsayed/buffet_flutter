# Figma redesign: decisions and mapping

**Status:** decided 2026-09-24; being built on `feat/figma-redesign`.
**Source:** Figma file `bKHrXIl431VsFoghgKyDBu` ("DEFI - Kitchen app"), Design and Components pages.
**Exports:** `design/figma/`, one PNG per frame at 2x, exported by hand (see *Access*).

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
those. Font details are read off the Figma UI by hand. A Dev or Full seat would restore the MCP.

## What the design covers, and what it does not

**Designed:** 8 frames, 390dp, **English/LTR only, light only, happy path only**:
Splash · Onboarding · Login (`Sign Up.png`) · Home · Drink Details · Order Summary · Tracking ·
Settings. The Components page (not exported) adds the logo, a card, add/subtract buttons and two
4-state stepper chips. The collapsed "+" and expanded "− n +" states are visible on Order Summary.

**Not designed:** Arabic/RTL (the primary locale) · lock screen · forced change-password · my
materials and the declare sheet · notifications · empty / loading / error / expired-session states ·
shortage warning · guest mode · cancel and the Cancelled state · **the whole staff view**.

These are **built in the same identity and approved from screenshot captures** (D8).

## Decisions

| # | Question | Decision |
|---|---|---|
| D1 | How to read the design | PNG exports in `design/figma/`; font details read by hand |
| D2 | Order flow | **(Choose a drink →) Drink Details → Review → Place.** No cart left on Home. See *Ordering* |
| D3 | Onboarding | **First-launch explainer**: the designed layout, shown once per install, skippable, with copy that explains the service instead of the coffee slogans, and no AI-generated stock photos |
| D4 | Employee navigation | **Bottom nav: Home · Favorites · Orders · Account.** These are the designer's tabs, except that "History" is named **Orders**, because it holds live orders as well as past ones. **My materials moves into Account.** Staff are unchanged: they land on `/queue`, with no bottom nav |
| D5 | Pickup or delivery | **The employee chooses per order, on Review**: "I'll pick it up at the kitchen" or "Deliver to: [location]". <br>• A location is required only for delivery. <br>• The app remembers the last choice. <br>• Staff see the choice on the queue card while preparing. <br>• The Ready wording follows the choice; an order with no recorded choice uses neutral wording. <br>This **needs the backend** ([request](backend-request-fulfilment-mode.md)) and ships as its own phase once the fields are in the contracts. Until then the Ready wording is neutral, since both happen today |
| D6 | Who closes a pickup order | **Staff or the employee.** Staff "Mark delivered" as today. The employee may also tap **"I picked it up"** on their own Ready pickup order; this is the designer's green "Pickup Order" button, given a real job. It needs `POST /orders/{id}/collected` (same request) |
| D7 | Fonts | **Inter for English, Cairo for Arabic.** Inter is confirmed from Figma: the heading sample is 600, 28/36. Both are bundled as assets under the OFL, with no pub dependency. English UI uses Cairo as the fallback, so Arabic item names still render correctly |
| D8 | Screens Figma does not cover | **Built directly in the same identity**, using the tokens and components taken from Figma. At the end of each phase, **screenshot captures (Arabic and English) are shown for approval before the commit.** This replaces "design before Dart" for screens that follow an already-designed identity (see *Rules this redesign changes*) |
| D9 | Backend requests | Drink description and menu group ([request](backend-request-drink-description-and-group.md)) · `StartedAtUtc` ([request](backend-request-order-started-at.md)) · **fulfilment mode and employee pickup confirmation** ([request](backend-request-fulfilment-mode.md)). The user implements them in `../buffet_app` |
| D10 | Branch | `feat/figma-redesign`, one commit per phase, never pushed |

## Visual language

**Palette:** sampled from the 2x exports; contrast figures are WCAG ratios. The code is
`lib/theme/brand_colors.dart`, where every figure is repeated beside its constant.

| Token | Value | Role | Contrast | Note |
|---|---|---|---|---|
| `brand` | `#1C4B9F` | Filled buttons, **input and outline-button borders**, field labels, headings, the active nav item | 8.21 white, 7.16 page | Figma's primary. The first 1x screenshot misread the input border as `#8DA5CF`; the 2x export shows it is this blue |
| `brandSecondary` | `#285EBE` | Card titles, **links** ("Change", "Forgot?"), the tracking timeline | 6.11 white, 5.33 page | Figma's own link and title blue. It replaces the `#1563EE` this file first proposed |
| `brandBright` | `#3871D7` | The selected chip's fill (white text), inactive nav labels on the white bar | 4.65 white | **Never text on the page** (4.06) |
| `iconBlue` | `#2A71F0` | Icons, the tab indicator, the inactive page dot, the input focus ring | 4.45 white, 3.88 page | **Non-text only** |
| `ink` | `#1C2F4B` | Headings and body text | 13.48 white, 11.75 page | Figma's dark text |
| `page` | `#E7F0FF` | Page background | — | Every kept semantic colour still passes on it: ok 4.52, warning 4.73, danger 5.73, violet 6.38, muted 4.94 |
| `brandLight` | `#D0DFF2` | Card borders, dividers, the top bar's edge | 1.35 white, 1.18 page | **Decorative only.** Figma's hairline |
| `outline` | `#6B8AC1` | The edge of an interactive non-primary control: an unselected chip, a stepper | 3.48 white, 3.04 page | Figma's chip edge `#B4CDEC` measured 1.42, so darkened, same hue |
| `muted` | `#5C6780` | Secondary text, hints, placeholders, the inactive tab label, the version line | 5.67 white, 4.94 page | Replaces Figma's greys, each measured on the ground it sat on: `#ACACAC` 2.27 and `#BEBEBE` 1.86 on white; `#8CBCF9` 1.71 and `#A1C0E4` 1.64 on the page |
| `ok` | `#0E7C5A` | Ready, Completed, "I picked it up" | 5.19 with white | Figma's `#00B67A` carried white text at 2.63 |
| `warning` | `#B54708` | Shortages, **the out-of-stock badge** | 4.73 page | Figma's grey badge (`#919191` on `#E2E2E2`) measured 2.43, and "out of stock" is a warning anyway |
| `danger` | `#B42318` | Sign out, cancel, errors | 5.73 page | Figma's `#BA1A1A` also passes; one red is kept |
| `accent` | `#6D22D8` | **"From my own jar", and nothing else** | 7.32 with white | Figma uses no violet in its UI. The input focus ring and the colour scheme's `secondary` were violet and are now blue, so violet appears nowhere else |

**Type:** Inter (English) and Cairo (Arabic). Arabic keeps line height 1.7; English takes Figma's
leading (heading 28/36 at 600, the other styles measured from the exports).

**Shape:** pill-shaped primary and outline buttons (55dp in Figma), rounded white cards on the
pale-blue page, circular icon buttons. Radii and spacing are taken from the exports and go into
`lib/theme/dimens.dart`. The 4px spacing scale is kept unless the design contradicts it.

**Chrome:** a light top bar (logo, bell with unread badge; a back arrow on pushed screens) replaces
the navy bar. `accentBright` existed to mark position on the navy bar and becomes unused. It is
removed rather than repurposed.

## Screen mapping

✅ taken · 🔁 taken, remapped to our data · ❌ dropped · ➕ added (missing from the design)

### Splash ✅
The pale gradient and centred logo lockup.

### Onboarding 🔁 (D3)
The layout is kept (hero card, dots, Next / Sign in, Skip). The three slides explain the service:
- order from where you are;
- staff prepare it, and you pick it up or have it delivered;
- bring your own materials and draw on them.

Shown once per install. Skip and Sign in both go to login.

### Login ✅ layout
- ❌ **Register** (primary button and footer link). Admins create accounts; there is no sign-up.
  The primary button is **Sign in**.
- ❌ **Forgot?** as a reset flow. There is no endpoint, and deliberately no SMTP. It becomes a sheet
  that says to ask the buffet admin to reset the password.
- 🔁 **Use Biometric** moves to the **lock screen**, restyled into the same layout. Biometrics
  unlock a *stored* token, and there is none at login.
- ➕ The language switch, which must stay on login (see CLAUDE.md).
- 🔁 The hint `mail@defi.com.eg` becomes the domain itself: the user types the name and the field
  shows `@defi.com.eg` beside it (guide §5.1, domain confirmed 2026-09-27). A full address still
  goes as typed.

### Home 🔁
| Figma | Ours |
|---|---|
| Logo · bell | ✅ logo · bell (unread badge). The metadata also had settings and avatar buttons, but they are not in the export, and the Account tab covers them |
| "Good Morning, Salma" | ✅ time-of-day greeting with `displayName` |
| Tagline "Boost your metabolism…" | ❌ a health claim with no data behind it |
| Search | ✅ client-side over `/catalogue`, matching `nameAr` and `nameEn` |
| Category chips | 🔁 Filters over the menu. The menu itself **keeps guide §7.1's source sections in every case: «من موادي» first** (violet, only when the user owns something), **then «من البوفيه»** (neutral). ✅ Built (2026-09-27, guide §7.9): All, then the menu groups in the server's order, with drinks that have no group (or a retired one) under «أخرى» / "Other"; they filter within both sections. While the server has no groups (`drinkGroups` empty, and on a deployment that predates them), the chips are the two source sections themselves, as jump links |
| "Popular" cards | 🔁 **Favourites.** Popularity does not exist, and the favourites are the user's own one-tap repeats. The strip rules still hold (4 most recent, measured two per row, retired items marked). **No "See all" on Home**: the Favorites tab is that destination, and a link to it would be a second control for the same place |
| "Recommended for you" | 🔁 **the full menu**: image, name, and up to two lines of description when one is written |
| "OUT OF STOCK" badge | 🔁 `inStock == false` shows a **warning badge and the row stays tappable**. Shortages never block |
| — | ➕ outstanding-order card (above everything while an order is live) · ➕ guest order entry (when `canOrderForGuests`) |

### Drink Details 🔁
| Figma | Ours |
|---|---|
| Top bar with no back arrow | ➕ **back arrow**. It is a pushed screen |
| Hero image, title | ✅ `imageUrl`, with the `ItemImage` fallback glyph |
| ★ rating | ❌ no ratings exist |
| Description | ✅ whole, under the name; omitted when none is written (guide §7.9) |
| "Choose size" S/M/L | 🔁 **Preparation** (`variants`), shown only when there is more than one |
| Extras chips | ✅ filtered by `allowedExtraItemIds`, with the double-portion mark kept |
| Sugar chip-stepper **and** sugar slider | 🔁 **one** stepper; 0 is an explicit "no sugar". A slider cannot make zero a stated choice |
| "Mint leaves" slider | ❌ an extra is one fixed serving; there is no amount |
| — | ➕ source choice, only when `hasOwnStock`: «من موادي» in **violet**, «من البوفيه» **neutral**. Violet never marks the buffet |
| Quantity stepper | 🔁 There is no per-line quantity, so the stepper sets how many **identical lines** the draft becomes. Nothing is hard-coded, and **only structural limits decide whether it is shown; a stock reading never does**: <br>• It is shown when `maxLines` leaves room for more than one line **and** the line's **requested** source structurally allows more than one: own jar (`drinkFromOwn == true`), or buffet when `maxBuffetDrinks > 1` or `capIsLifted`. Lines already added count by their *requested* jar, never by whether a jar reads empty (a stock reading). <br>• An own-jar drink whose jar reads empty (`ownServingsLeft <= 0`) **keeps the stepper**. Its lines resolve to buffet stock and count against the buffet cap (guide §7.1.1), but that is a stock reading, so the cap is enforced at the point of adding, **with the reason stated**, and never by hiding or disabling. <br>• **This needs a quantity-aware gate** (Phase 5): today `draftWouldExceedBuffetCap` (`composer_controller.dart:291`) and `addLine` (`:534`) treat the draft as exactly one line, and the buffet-cap banner (`composer_screen.dart:485`) follows them. The controller gains a draft quantity: `addLine` commits N identical lines, and the gate and the banner count the draft as N. Existing controller tests stay untouched; new ones cover the quantity |
| "Add to Orders" | 🔁 **Continue** → Review |

### Review order (Figma "Order Summary") 🔁
- ✅ Lines with thumbnails, notes, **Place order**.
- 🔁 "Delivery To / Change" becomes the **fulfilment choice** (D5): pick up at the kitchen, or
  deliver to a location. Until the backend ships it, this stays the free-text location field of
  today.
- 🔁 The per-line "+" / "− n +" stepper follows the same rule as the Drink Details stepper:
  identical lines, within the caps.
- ❌ Payment, promo code and price breakdown. They are already hidden in the Figma frame, and there
  is no money in this system.
- ❌ "The final step to your elevated ritual." Plain wording instead.
- ➕ Removable lines; "Add another drink" while `lines < maxLines` (it returns to **Choose a
  drink**; the buffet cap is enforced when the line is added, as today); save-as-favourite; the
  guest's name, shown as a statement. It was entered first, on Choose a drink (see *Ordering*).
- A favourite tap seeds the flow and lands **directly on Review**.

### Orders tab and Tracking 🔁
- The tab's **Process / Done** segments (from the Tracking frame) split live orders from past ones.
  They are labelled «قيد التنفيذ» / «سابقًا» ("In progress" / "Earlier"). **Ready sits under In
  progress**, first, because the order has not stopped moving. Each tab has its own empty state and
  pull-to-refresh. Save-as-favourite stays on finished orders only.
- 🔁 The design's tracking frame holds a single order's lines. The tab holds a **list** of orders
  instead, since a user can have several at once. Each row is titled by its drinks («قهوة ×2،
  شاي») **in the reader's language, from the catalogue**, the same names the status screen shows.
  The status word sits under the title, then the date and place.
- Figma has 5 steps; we have 4 statuses. "Kitchen takes order" and "Preparing" are both
  `InProgress`, so the timeline is **Sent → Being prepared → Ready → Completed** ("Received" in
  English). It is vertical, as in the design, with each step's time where the API has one. The
  summary card no longer repeats the placed and ready times.
- `Ready` is the loudest state, in `ok` green with its word, never colour alone. Its wording is
  neutral until the fulfilment mode ships, then it follows the mode (D5).
- 🔁 The green **"Pickup Order"** button becomes **"I picked it up"**. It is shown only on the
  caller's own Ready pickup order, once the backend ships `/collected` (D6).
- 🔁 **"NEW ORDER"** becomes New order.
- ❌ "Receipt Order": no money.
- ➕ Cancelled state, Cancel (Pending only).
- The line summary follows the Figma pattern: preparation · N spoons · extras. "×3" is identical
  lines grouped for display.

### Account (Figma "Settings") 🔁
- ✅ Name, Logout (in `danger`).
- ✅ Version (in `muted`, not Figma's unreadable tint), from `package_info_plus` (decided
  2026-09-27), with the build number. "Built for DEFI" is left out.
- 🔁 "Member since" becomes **department**, which we have.
- ➕ **My materials** row. It opens the materials screen and the declare sheet (D4).
- ❌ Order History (duplicates the Orders tab), Payment Methods, Notifications (the bell already
  reaches it), Help Center (no content), Share.
- ➕ Language, biometric toggle, change password, and the admin-on-web note. Each is a stacked
  card row like the design's; sign-out is the last row, in `danger`, with no chevron.
- ➕ **Change password** opens `/password`, the same screen as the forced first-run change. It reads
  the auth stage: signed in, it asks for the current password, says "Save", and on success confirms
  and goes back. The forced `/change-password` is unchanged: no current password, "Save and
  continue", and no way back (rule 10). A user in the forced stage is bounced off `/password` like
  every other route.

## Ordering (D2)

The composer is **one route (`/order`) hosting three steps**, `ComposerStep`: Choose a drink →
Drink Details → Review. It shows the design's three screens, but the whole flow is one order: one
draft, one guest name, one idempotency key. One screen owning all of it means none of that can be
dropped between routes, and the controller's guarantees did not move.

1. **Choose a drink** (`steps/choose_drink_step.dart`): the favourites strip (with "See all", since
   there is no nav bar here), search, and `DrinkMenu`, the same menu Home shows.
   - It is where the flow starts for **staff** (the queue's "order for myself"), for **guest mode**
     (Home's guest entry), and for **"Add another drink"**.
   - In guest mode the **guest name is its first field**. That preserves "guest mode asks for the
     name first", and it means `capIsLifted` already holds by the time a quantity stepper is shown.
     **Every way off this step runs the name check**: a menu row, a favourite, and the "N drinks in
     this order" card. With no name, the error shows on the field and the step stays put.
     Nothing is disabled.
2. **Drink Details** (`steps/drink_details_step.dart`) edits the draft. It shows the jar choice
   (violet for "my materials", brand for the buffet; only when the user owns the drink), the
   preparation, sugar, extras and the quantity stepper.
3. **Review** (`steps/review_order_step.dart`) holds:
   - the lines, with the draft at its quantity;
   - identical added lines shown once as ×N, with "one fewer" and "remove";
   - location, notes, save-as-favourite and Place order.

**Where it starts**, from the seed:
- a favourite opens on Review, or on Choose if its drink was retired;
- a Home menu row opens on Drink Details;
- everything else opens on Choose.

**Back unwinds the steps before it leaves the route.** It is `PopScope`-driven, and three rules keep
it sensible:
- **"Add another drink"** commits the draft and stacks Choose **on top of** Review, so back returns
  to the order rather than discarding it.
- **Continue** returns to the Review already in the flow rather than stacking a second one.
- **Removing the draft** also drops the Drink Details step that edited it, so back never lands on a
  step with no drink.

**Quantity** (`draftQuantity`) is identical lines; there is no per-line quantity on the wire.
- `maxDraftQuantity` takes only structural limits into account: the room under `maxLines` and, for
  a drink *requested* from the buffet, the room under the buffet cap. Lines already added count by
  their **requested** jar, never by whether a jar reads empty.
- An own-jar drink that reads empty keeps its stepper. The cap then shows on the drink step and on
  Review, and `addLine` refuses past it with the banner saying why.

Everything the controller guaranteed before still holds, and the existing controller tests are
unchanged (`composer_quantity_test.dart` covers what is new):

- The idempotency key is minted when the flow opens, kept across every step and every retry, and
  discarded only on confirmation.
- `setMode` never mints a key.
- `mode` and the favourite fields stay in both `ComposerState` constructor calls.
- The buffet cap is enforced when a line is added, and it counts the quantity.
- Place order is disabled only when the order holds nothing, and then Review says so, with a way
  back to the drinks. It is never disabled on stock or a missing guest name; a missing name takes
  the user back to the field with the error showing.

## Rules this redesign changes (CLAUDE.md is updated as each lands)

| Old rule | New rule |
|---|---|
| The employee landing screen is the home hub with a permission-aware action grid | The landing screen is the **Home tab** of a bottom-nav shell (**Home · Favorites · Orders · Account**): outstanding order, favourites, menu. My materials is reached from Account |
| `home_screen_test`: "New order" reachable without scrolling at 320dp | There is no "New order" button; a menu row opens the composer. The search field and the outstanding order are reachable above the tab bar at 320dp with a full favourites strip, and with no favourites the first menu row is too. (The first row cannot be pinned with a full strip: it lands just below the fold, measured) |
| Notifications and settings live in the home app bar only | The bell lives in the top bar; settings is the Account tab. Still one control per destination |
| The favourites strip truncates only when a "show all" destination exists, which it links to | On Home the destination is the **Favorites tab**, so the strip carries no link of its own. On Choose a drink (no nav bar) the "See all" link stays |
| Ordering is one screen (guide §7.1) | Ordering is (Choose a drink →) Drink Details → Review: three steps of one route (see *Ordering*) |
| The favourites strip lives on the composer as well as the hub, because staff never see the hub | It lives on **Choose a drink** as well as Home, for the same reason |
| Guest mode asks for the name first | Unchanged in substance: the name is the first field of Choose a drink |
| Ready is the "come and collect it" moment (guide §4.3; `readyBody`, `outstandingReadyBody`, `alertReadyBody`, `channelReadyDescription`, `handoverTab`, `noHandoversBody` in the ARB files) | Ready is still the loudest state, but its wording is **neutral** until the fulfilment mode ships, then **per mode** (D5). Android should update an existing channel's *description* when the channel is re-created with the same id, which the `@channelReadyName` note ("frozen") does not cover; **verify on a device** |
| Only staff close an order | Staff close any order; the employee may also close their own **Ready pickup** order (D6, once shipped) |
| Theme tokens are ported verbatim from the web's `site.css` (CLAUDE.md, guide §2.2) | Tokens come from Figma, fixed for contrast. **The app and the web app now differ in palette** unless the web is restyled too |
| Design before Dart: every screen is designed and approved before widgets are written | The identity is designed (Figma plus this file). Screens Figma lacks **follow it and are approved from screenshot captures before the phase's commit** (D8) |

## Open

Nothing blocks the client work. The phase that builds pickup or delivery, and "I picked it up",
waits on [backend-request-fulfilment-mode.md](backend-request-fulfilment-mode.md); the client
never sends or reads a field before it is in `docs/contracts/`.
