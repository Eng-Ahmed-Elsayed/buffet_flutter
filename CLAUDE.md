# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current state

**A Figma redesign is in progress on `feat/figma-redesign`.** The decisions, and the screen-by-screen
mapping of what was taken, remapped and dropped, are in
[docs/figma-redesign.md](docs/figma-redesign.md). Read it before touching any screen. The headline
changes:

- Employees get a bottom-nav shell: Home · Favorites · Orders · Account, with My materials inside
  Account.
- Ordering becomes (Choose a drink →) Drink Details → Review.
- The palette moves to the Figma blues, fixed for contrast.
- English text uses Inter, with Cairo for Arabic.
- Pickup vs delivery becomes a per-order choice, and the employee can confirm a pickup. This waits
  on [a backend request](docs/backend-request-fulfilment-mode.md).

Until each phase lands, the rules below describe the app as it stands; the "Rules this redesign
changes" table in that document says which are about to move. Figma MCP is capped on the current
seat, so the design is read from the PNG exports in `design/figma/`.

**Scaffolded and building.** The five screens from §1.2 exist, in both locales, on branch
`feat/app-scaffold`. `flutter analyze` is clean and `flutter test` passes.

**The domain rules are verified against the running server**, not just against the contracts — see
the table at the top of [docs/backend-findings.md](docs/backend-findings.md). Stock deducting at
`Ready`, shortages returning `200`-with-warnings, the `202` that creates nothing, `403` on staff
declarations, `404` (not `403`) on another user's order, and idempotency were all exercised with
the test accounts.

Two open backend issues, neither fixable from the client:

1. **Client-written Arabic is stored as `?`** — `notes`, `locationText`, `lineNote` and the cancel
   reason. Specified in
   [docs/backend-request-arabic-encoding.md](docs/backend-request-arabic-encoding.md). This is the
   one that matters: an Arabic-first app where users cannot write Arabic.
2. **`/auth/login` ignores `Accept-Language`** and returns Arabic either way. The client is already
   correct per §4 — it sends the header and surfaces `ApiError.message` verbatim.

`MyMaterialDto.imageUrl` **has shipped** and works; the materials screen shows real uploaded
photographs, falling back to a category glyph when the field is null or the file 404s.

Since built: the settings screen with the language switch, **biometric unlock** (§6, with the
`locked` stage in the auth machine and all four failure modes handled), and **launcher icons** from
the brand mark (`tool/generate_launcher_icons.py` regenerates them — no `flutter_launcher_icons`
dependency).

The **in-app notification centre is built** (§7.4) — list, unread badge on both home screens, and
mark-all-read on open. It is the reliable half of notifications: the server writes the row before it
attempts a push, so a push that was throttled, deferred by Doze or never permitted is still
recoverable there, and it is the only place `LowStock`, `DeclarationConfirmed` and
`DeclarationRejected` ever surface. **The rows new on opening keep their mark** (a named dot and
bold text, never the fill alone) after mark-all-read reloads them as read; the snapshot is taken
before marking. A declaration outcome opens My materials, for employees only. **`LowStock` leads
nowhere, deliberately**: the server sends it only to admins, and it concerns buffet stock, which
nothing in the app shows. `account_notifications_test.dart`. Sign-out asks first.

**Push is built, Android only** (§7.4). Firebase project `digital-buffet-846f0`; the service
account lives in .NET user secrets (`Push:ServiceAccountJson`) and never in either repository.
`OrderReady` and `OrderCancelled` are the only two kinds that push — see §7.4 before adding a third.

**iOS has no push and will not until an Apple Developer account is funded.** That is a deliberate,
recorded gap, not an oversight: do not write untested APNs code to fill it. What both platforms do
have is a local notification with sound when a poll sees an order turn Ready or Cancelled
(`lib/data/local/order_alerts.dart`). **What it covers is the app in the foreground, on any
screen**: `OrderStatusTracker` on Home (which stays mounted beneath every tab and pushed screen)
compares each settled load of the order list, so the chime no longer depends on the tracking
screen being open. It stays silent on the first load after a return, where the change is on screen.
**After the app leaves the screen it keeps looking for up to three minutes**
(`BackgroundOrderWatch`, decided 2026-09-27), but only while an order is still being made and only
where no push will announce it: iOS, or an Android device whose registration failed. A registered
device stays quiet, or Ready would ring twice. It calls the repository directly, because a provider
refreshes on the next frame and a backgrounded app draws none. **The OS decides how long it really
runs**: iOS grants the background time `AppDelegate.swift` asks for, about half a minute, so a
drink that takes three minutes will usually not chime on an iPhone; an Android process is frozen
soon after it is cached. Beyond that only push helps. Staff are not covered: it lives on Home, as
the foreground tracker does.
`background_order_watch_test.dart`. A tap on the alert opens the order through
the same held-link path as a push. Nothing on the device can cover the process being killed.

Still unverified: **push on a physical Android handset with the app force-stopped.** That is the
case the whole feature exists for and no emulator or test exercises it — see
[docs/firebase-setup-checklist.md](docs/firebase-setup-checklist.md). The plan is
`~/.claude/plans/staff-view-expressive-lecun.md`.

Two rules from that work that a future edit must not undo:

- **The staff undo affordance lives on the card, not in a SnackBar.** `ScaffoldMessenger` *queues*
  snackbars and their duration counts from display, not creation, so a rush showed undo buttons for
  orders that had already been served. Do not "simplify" it back.
- **A committed serve's card goes at once and stays gone until its answer lands.** It is removed
  as the undo window commits (as a handover's is) and filtered out of every refresh while its
  `/ready` is in flight (`_serving`): a poll answered first still lists it Pending, and live Ready
  buttons coming back read as "undone" and got the drink made twice. Put back only if the serve fails.
  **A shortage from "ready and handed over" is shown above the tabs**, named, until dismissed,
  since that order leaves both lists and its card with it. `queue_serve_test.dart`.
- **The pending bar is announced once, with the seconds left when it appeared.** Its live region
  used to carry the ticking count and was re-read every second. There is no press-to-pause: it
  stopped the bar but not the commit, so the bar lied. **A handover card can be cancelled**: the
  server re-books a Ready order's consumption as waste, and the dialog says so. The dialog's buttons
  are "Keep order" and "Cancel order", never "Cancel"/"Confirm". Identical cups show once with ×N,
  where identical means every field the maker acts on. The two tabs carry their counts, scroll
  and grow in height rather than fade a label (`measureTabLabels`). **"Start making" (`/start`)
  is optional, never a gate**: a Pending card offers it above the ready pair, which still serve a
  Pending order directly, and an InProgress card says "being made" in its place. It is a text
  button, so Ready stays the largest target. It is immediate, with no undo, since it writes no
  ledger rows, and it is announced. `queue_staff_view_test.dart`.
- **Foreground polling stays alongside push.** Push closes the closed-app gap; polling closes the
  foreground-freshness gap. They are not duplicates.
- **`prepareLandingPrompts` is called from BOTH landing screens** (`lib/app/landing_prompts.dart`).
  It is also what registers for push, so a new landing screen that skips it never gets push. It
  asks one thing at a time: the biometric offer, then the notification permission, then push
  registration. A notification tap does not wait on any of it. It used to live on the composer,
  which is the *employee* landing screen — so staff, who only reach the composer by pushing it from
  the queue, had no notification channels and were never asked for permission at all. A new landing
  screen must call it.

**The Flutter SDK lives at `C:\src\flutter` and is not on `PATH`** — invoke it by full path
(`C:\src\flutter\bin\flutter.bat`).

**Employees land in a bottom-nav shell** (`lib/app/employee_shell.dart`, a
`StatefulShellRoute`): **Home · Favourites · Orders · Account** at `/home`, `/favourites`,
`/orders`, `/account`. Home is the design's Home: greeting, drink search (`foldForSearch`, which
treats «قهوه» and «قهوة» as the same), the outstanding-order card, the favourites strip and the menu
of every drink grouped «من موادي» then «من البوفيه». **There is no "New order" button; a menu row
is the way in.** It opens the composer seeded with `ComposerSeed.drinkItemId` and `drinkFromOwn`,
the row's jar. Home builds its whole menu (a `Column`, not a lazy `ListView`), because the jump
chips scroll to a section heading and a lazy list never builds an off-screen one. My materials is a
row on Account. Staff still land on `/queue`, with no bar, and
push what they need from there. Each role has exactly one landing, and `signedInRedirect` (in
`router.dart`, tested directly by `landing_route_test.dart`) bounces staff off every tab and
employees off the queue. Three rules a future edit must not undo:

- **Back is handled by the shell, never by a tab.** go_router asks a tab's own navigator only when
  it can pop; a tab root cannot, so the gesture goes straight to the shell page. From any tab but
  Home it returns Home; on Home, `ExitConfirmation` asks. A guard placed on a tab screen is never
  asked, and the app simply closes. `employee_shell_test.dart` drives this through the real
  `handlePopRoute`; keep it that way.
- **Steps in a task are pushed above the shell, on the root navigator**: the composer, order
  status, notifications, My materials, `/favourites-list`, `/settings` (staff), `/password`. Never push a tab's
  path from inside a flow; that would stack a second shell.
- **Never build a `GoRouter` at test-file load time.** It initialises the wrong binding and fails
  the whole file. Build it in `initState` or inside `testWidgets`.

**The composer is one route with three steps**, `ComposerStep` Choose a drink → Drink Details →
Review ([docs/figma-redesign.md](docs/figma-redesign.md), *Ordering*). It is not three routes:
the draft, the guest name and the idempotency key belong to one order and one screen owns them.
Rules a future edit must not undo:

- **Back unwinds the steps before it leaves** (`PopScope` plus `_steps`). "Add another drink"
  stacks Choose **on top of** Review, because clearing the stack made back discard every line
  already added. Continue returns to the existing Review rather than stacking a second one.
  Removing the draft drops its Drink Details step, so back never lands on a blank step.
- **Quantity is identical lines** (`draftQuantity`), capped by `maxDraftQuantity` from structural
  limits only: lines count by their *requested* jar, never a stock reading. An own jar that reads
  empty keeps its stepper; the cap is enforced when adding, with the reason stated.
- **Place order is disabled only for an empty order, and Review then says so** with a way back.
  A missing guest name takes the user back to the field instead.
- **Home and Choose a drink render the same `DrinkMenu`**, so the two can never list drinks
  differently. It must sit in a non-lazy scroll view (see Home).
- **A favourite is replayed whole**: every line, the earlier ones added and the last as the draft,
  within the line cap **and the buffet cap**. What does not fit, or has been retired, is named in a
  notice; it is never dropped silently. Replaying only the first line placed a different order from
  the one saved.
- **`/favourites-list` returns its pick to the composer that opened it** (`returnsPick`). It
  used to push a second composer, and two composers share one provider: a guest name was wiped, the
  idempotency key was shared, and a staff member's served confirmation was lost.
- **Leaving asks before discarding an order** (Review with drinks, lines already added, or a failed
  placement), and never mid-placement. A single drink opened from Home backs out freely.
- **A failed placement stays on Review** until the next attempt, scrolled into view with the
  keyboard lowered, never a SnackBar over the retry button. Only an uncertain failure (no
  response, or a 5xx) says the order may have gone through; a 4xx is a refusal with the server's
  reason. The notices live inside the step's scroll view, via its `header` slot, so they never
  squeeze the step at 320dp. `composer_journeys_test.dart` pins all of this.

**The Orders tab has the design's two tabs**: In progress (Ready first, then Pending and
InProgress) and Earlier (Completed and Cancelled). The tracking screen shows a vertical four-step
timeline (Sent → Being prepared → Ready → Received) and carries the order's times, so the summary
card does not repeat them. Rules a future edit must not undo:

- **Ready wording is neutral** («جاهز لك», "it's ready for you") until the fulfilment mode ships
  (D5). Both pickup and delivery happen today, and "come and collect it" was wrong for the
  delivered half.
- **An order row names its drinks from the catalogue in the reader's language**, exactly as the
  status screen does, falling back to the stored `drinkNameAr`. `OrderSummaryDto` carries Arabic
  names only, and a row saying «قهوة» that opens onto "Coffee" names one drink two ways.
  `order_tracking_test.dart` pins it in English.
- **Times say the day only when it is not today** (`Formatters.moment`), in the list and on the
  timeline alike. A finished order's last step is announced as done, never as the current step.

**The Account tab is the design's Settings frame**: the name and department, then stacked card
rows. The rows are My materials (employees only), Change password, the biometric switch (its own
card, drawn only on a device that can use it), Language, and Sign out in `danger`. **Change password
is `/password`, a separate route from the forced `/change-password`**, and the same screen serves
both by reading the auth stage. Signed in, it asks for the current password and pops with a
confirmation. Forced, it never asks for the current password and never lets the user back. The
forced stage bounces every route, `/password` included, so rule 10 holds without a special case.
The design's Version line is at the foot, from `package_info_plus` (`appVersionProvider`),
with the build number after it.

**Sign-in asks only for the name before `@defi.com.eg`** (`ApiConfig.emailDomain`, §5.1). The
domain shows beside the name, on its right in both languages, since the field is LTR; a full
address, typed or pasted, goes as it is, which is how the `company.com` test accounts still sign
in. **Every digit is Latin**, dates included (`Formatters` sets `useNativeDigits = false`), and
no translation writes an Arabic-Indic one (`test/l10n/digits_test.dart`).

**An extra's violet follows the jar it is drawn from, not ownership.** Ticking an extra the user
owns, with servings left, puts it in `ownExtraItemIds`. A source row under the extras (the same
`_SourceChip` as the drink's) switches it to the buffet. The chip used to be violet whenever the
user owned some, while the order sent it as buffet stock. **There is no sugar jar toggle**,
deliberately: the UI never picks a sugar item (the server auto-resolves it), and `sugarFromOwn`
with no sugar item is unverified against the server. `composer_own_extras_test.dart`.

**Route transitions and bottom sheets stop moving under reduced motion.**
`ReducedMotionPageTransitionsBuilder` wraps Android's, Windows' and Linux's transitions, and every
`showModalBottomSheet` passes `sheetAnimationStyle: Motion.sheet(context)`. iOS keeps Cupertino's,
because bypassing it removes the edge swipe back. `test/theme/reduced_motion_test.dart`.

**The catalogue's `usual` is gone and must not come back.** It was the caller's last
non-cancelled order presented as a habit — no frequency, no weighting — and it moved under the user
every time they ordered for a visitor. **Favourites** (`GET`/`POST`/`DELETE /favourites`, §7.6)
replaced it: the same one-tap repeat, stated rather than guessed. The whole point of the removal was
that two shortcuts side by side, one silently moving, is worse than either alone, so **never add a
"last order" card next to the strip**. The rationale and the shipped inventory are in
[docs/backend-change-usual-removed.md](docs/backend-change-usual-removed.md). Four rules from it:

- **A tap seeds the composer; it never places the order.** The user confirms what they are
  ordering, and a favourite holding a since-retired item shows as a visible line rather than an
  opaque rejection. Favourites are deliberately **not** pre-filtered server-side — let the order be
  the thing that fails.
- **The strip lives on the composer's Choose-a-drink step as well as Home**, for the same reason
  `prepareLandingPrompts` does: staff never see Home, they push the composer from the queue.
- **`ComposerSeed` carries the whole `FavouriteDto`**, not an id — favourites are a separate
  endpoint from the catalogue, so an id would mean a refetch between the tap and the drink. And
  `saveAsFavourite` / `favouriteName` / `fromFavouriteId` must stay in **both** `ComposerState`
  constructor calls, exactly like `mode`.
- **`maxFavourites` is the one cap that may disable a control**, because it is structural — the
  server refuses past it — and only ever with the banner beside it saying so. Never a stock reading.
- **The strip shows four *most recently used*, then defers to the full list** — and truncates
  **only when a "show all" destination exists**, since hiding a favourite behind a link that is not
  there loses it as silently as filtering a retired one out. On Home that destination is the
  **Favourites tab**, so the strip passes `restReachableElsewhere` and draws no link. On the
  composer it links to `/favourites-list`. Sorted by `lastUsedAtUtc`, which is what that
  field is published for.
- **The strip's tiles are measured two-per-row, never a fixed `maxWidth`.** A 220dp cap put one card
  per row on a 320dp phone, and four favourites pushed "New order" — then the primary action of the
  whole app — out of the built viewport entirely. The responsive suite did **not** catch it, because
  it checks for overflow and nothing overflowed. `home_screen_test.dart` now asserts that the
  **search field and the owed order** (the first ways into ordering, placed above the strip) are
  reachable without scrolling **above the tab bar**, with Home inside the real shell. With no
  favourites, the first menu row must be in reach too.
- **A favourite whose item an admin retired is shown and marked, never hidden or disabled.** The
  server does not filter these (§7.6), and it is right not to: one that vanished silently would
  leave the user nothing to act on and no way to delete what they cannot see. It still taps — the
  composer is where the missing drink becomes a visible line. `favourites_strip_test.dart` pins it.
- **A favourite is a heart everywhere**, as the design's tab bar draws it. A star beside a heart
  read as two different things.
- **An order already saved says so; it does not offer to save again.** `FavouriteDto.orders()`
  compares only what is *ordered* — drink, preparation, sugar, extras — ignoring the name and the
  jar, so two saves of the same coffee are one favourite. The action is **replaced by a statement**,
  never greyed out.

**One destination, one control per screen.** The bell lives in Home's top bar **only**; settings
is the Account tab, and My orders is the Orders tab. None of them has a tile or an icon on Home as
well, because the same destination twice on one screen (once in the chrome, once in the body) is
noise. The unread badge lives on the bell alone for the same reason. Pinned by
`test/features/home_screen_test.dart`.

**Both landing screens carry the brand lockup in their top bar**, Home and the staff queue alike.
Each is named for screen readers (`homeTitle`, `queueTitle`), since the lockup is decorative. The
queue's lockup scales down so its three actions still fit at 320dp; its two tabs carry their counts
(`queue_undo_test.dart`).

**A failed refresh keeps what is on screen, and says so.** My orders, notifications, the queue and
the tracking screen all keep their last data with a "Couldn't refresh" notice and Retry. A
background poll that fails must never swap a Ready order, or the notification being read, for an
error screen (`skipError: true`); only a first load with nothing to show falls to the error state.
Errors are worded by `describeError` (`lib/shared/error_text.dart`), never by a provider's
fallback string, which reached the screen as the literal word "network". The bell's badge is
refreshed by Home's poll, resume and pull-to-refresh, and by every queue refresh. A labelled
button in an `InlineBanner` goes in `action` (under the text), never `trailing`, which squeezed
the message at large text scales. `staleness_test.dart`.

**A validator always returns words**, from the ARB files, never `''`. An empty message is a red
border alone (colour as the only signal, and nothing for a screen reader), and on the new-password
field it also hid the "at least 8 characters" helper at the moment that rule was broken. The
declare sheet's «الصنف غير مدرج» is a sentinel value of its own; `null` means nothing chosen yet.

**A labelled field is a `LabelledField`, never `MergeSemantics` around a label and a field.**
The label goes on the field's own node, as written rather than in the display capitals. Merging
also merged the field's own controls, so the eye toggle on a password field stopped being a button
a screen reader could reach. A button's working state is `ButtonSpinner`: brand blue and named.
The white one was 1.43:1 on the disabled fill. A danger `InlineBanner` is a live region, so a
failure is announced as it appears. The lock's button says «فتح القفل» / "Unlock", never a
sensor, since the prompt may be a face, a fingerprint or the device PIN.
`entry_accessibility_test.dart`.

**The first-launch explainer (`/welcome`) shows once per install, before the first sign-in, and
never to someone who already uses the app.** Its flag lives in `PreferencesStore` and survives
sign-out. **Any session stage (signed in, locked, forced password change) marks it seen**; see
`onboardingControllerProvider`. Without that, everyone who signed in before it existed would be sent
through three slides the moment their session ended, burying the "session expired" notice below.
`signedOutRedirect` holds on the splash while the flag loads. The entry screens (splash, explainer,
sign-in, lock) share `BrandBackdrop` and `BrandLockup`. **No text sits over the glow's peak**: the
link blue drops to about 4:1 there, so the explainer's Skip is in ink.

**The forced password change survives a relaunch** (rule 10). `pref_must_change_password` is
written by login *before* the token, restored on cold start **ahead of** the biometric lock, and
released only by set-initial-password's `204`. Before this, killing the app and reopening it was a
way past the block. The forced screen therefore has one exit, **Sign out**, which removes the token
and the flag together. `session_restore_test.dart` pins all of it. Two rules from the same fix:

- **A 401 ends only the session it belongs to.** The interceptor acts only when the failing
  request's bearer is the token stored *now*. A slow request on an old token must not end the
  session the user has just signed into. `unauthorized_interceptor_test.dart`.
- **An ended session leaves nothing behind.** A real 401, and a token found expired at cold start,
  clear what sign-out clears: the biometrics flag, the enrolment sentinel, the identity and the
  forced-change flag. Otherwise the next person to sign in inherits the previous one's fingerprint
  lock. The cleanup is best-effort: sign-in waits for it but never fails on it.

**An expired session says so on the login screen.** A `401` clears the token and drops the user at
login, and so does a token found expired at cold start (`hasExpiredToken`), which is how most
30-day sessions actually end; `AuthState.sessionExpired` (surfaced by `sessionExpiredProvider`) is what makes that legible,
since the token lasts 30 days with no refresh endpoint and this lands on somebody mid-task who did
nothing wrong. It is never set by a failed sign-in — the login request carries
`ApiConfig.skipAuthFlag`, so its `401` is a wrong password and belongs on the field.

**The language switch is on the login screen as well as in settings.** Settings sits behind the
sign-in that login gates, and the app opens in Arabic regardless of the device language — so
without it an English-speaking user cannot read the screen they must sign in on, and has no way to
fix that. It also sets `Accept-Language`, so it changes the language of sign-in errors. Covered by
`test/features/login_language_test.dart`; login is now in the 320dp responsive suite too, because
its two segments are labelled in different scripts and cannot be shortened.

**Guest ordering is a composer *mode*, not a field.** `ComposerSeed` travels as `GoRouterState.extra`
(never a query parameter — a URL must not be able to assert a privilege the token may not carry).
Self mode shows no guest field at all; guest mode asks for the name first and requires it. Two rules
a future edit must not undo:

- **`setMode` never mints a new idempotency key**, and `addLine()` / `resetAfterConfirmedOrder()`
  rebuild `ComposerState` field by field — so `mode` must stay in both constructor calls or a second
  drink silently drops the user back into a self order. Covered by `test/features/composer_mode_test.dart`.
- **The guest name gates the order button but never disables it.** The handler reveals the error on
  the field instead; a disabled control with no stated reason is the dead end this codebase avoids.

## What this repo is

The Flutter client for the Digital Buffet ordering system — **employee view and staff view only**.
Admin work (import, reporting, audit) stays on the web and must not be built here.

The backend is a separate ASP.NET Core 10 repository at `../buffet_app`. Paths in the docs like
`src/BuffetApp.Web/Api/StaffApi.cs` refer to *that* repo. The C# wire contracts have been copied
verbatim into [docs/contracts/](docs/contracts/) — mirror those field-for-field when writing Dart
models (the wire is `camelCase` via System.Text.Json defaults).

## Authoritative documents

- [docs/flutter-app-guide.md](docs/flutter-app-guide.md) — the build reference. §0 (live API and
  deviations), §2 (brand tokens), §3 (architecture), §5 (auth state machine), §7–8 (screen rules),
  §12 (definition of done, usable as a review checklist).
- [docs/archive/staff-api-spec.md](docs/archive/staff-api-spec.md) — staff endpoints, plus the four documented
  deviations at the end.
- [docs/figma-redesign.md](docs/figma-redesign.md) — the redesign decisions: what was taken from
  Figma, what was remapped onto the business, what was dropped, and why.

These documents are authoritative for **meaning and behaviour**. A design (see below) is
authoritative only for layout and dimension. Where the Figma design and the guide disagree,
`figma-redesign.md` records the decision.

## Workflow: design before Dart

Screens are designed and approved *before* widgets are written. **The identity is now designed**:
the Figma exports in `design/figma/` plus [docs/figma-redesign.md](docs/figma-redesign.md). A
screen Figma covers is built to its export. A screen Figma does not cover (Arabic/RTL, the staff
view, My materials, the lock screen, states) is built in the same identity, from the same tokens
and components. It is then **approved from screenshot captures (Arabic and English,
`test/screenshots/`) before the phase is committed**. A screen that departs from the identity, or
a new pattern with no precedent in Figma, is still mocked up first.

§1.2 names the five screens that carry the domain rules; §1.3 names what must deliberately **not**
be designed (a staff declarations tab, a sugar name on the queue card, a guest-order screen, any
admin screen).

Ask for the *states*, not just the happy path: shortage warning that does not disable, an order
sitting in `Ready`, empty catalogue, expired token.

## Domain rules that the API shape does not reveal

These are the ones most likely to be broken by someone reading only the contracts:

1. **Stock is deducted at `Ready`, not `Completed`.** `Ready` = the drink was made; `Completed` =
   handed over. `POST /staff/orders/{id}/ready` is the only path that writes ledger rows.
2. **Shortages warn but never block.** `/ready` returns `200` with a `warnings` array, never `400`.
   Never disable a control on a stock reading — physical and recorded stock drift, and halting
   service is worse than a negative number an admin reconciles.
3. **Violet (`accent`) means "from my own jar"**, everywhere. Never reuse it for generic selection.
4. **A declaration creates nothing** until an admin confirms receipt. `POST /materials/declare`
   returns **`202 Accepted`** — say "awaiting confirmation", never "added".
5. **Compare order status by name, never by ordinal** (`Ready = 4`, out of workflow order). Send
   and compare the string name.
6. **Arabic RTL first.** Only `start`/`end` (`EdgeInsetsDirectional`, `AlignmentDirectional`),
   never `left`/`right`. Bidi-isolate any quantity-plus-unit string — unit names are admin-entered
   and keep whatever language they were typed in.
7. **Declaration endpoints are admin-only.** A `Staff` token gets `403` on all three
   `/staff/declarations*` endpoints. This is separation of duties, not an oversight — do not build
   the tab.
8. **`StaffOrderLineDto.SugarNameAr` is always null.** The queue card shows spoon count and source
   owner instead.
9. **`GET /staff/queue` returns `Pending` + `InProgress` only.** `Ready` orders need a separate
   `?status=Ready` fetch for the handover list.
10. **`mustChangePassword` is not dismissible.** The token works, so a careless client could skip
    the screen and order anyway. Block navigation until `204` from `/auth/change-password`.
11. **Never queue orders offline.** Fail the placement, keep the composer filled, let the user
    retry with the *same* idempotency key.

## API essentials

Base URL `https://<host>/api/v1`. **JWT bearer only** — cookie auth is deliberately rejected
because the API has no antiforgery tokens. Never drive the MVC screens from the app.

- Tokens last 30 days and **there is no refresh endpoint**; biometric unlock exists to make
  re-login rare, not to extend the session.
- Send `Accept-Language`; error messages are localised server-side. Surface `ApiError.message`
  as-is rather than mapping codes to client strings.
- Map `401` centrally in a Dio interceptor: clear the token, route to login, do not retry.
- Every timestamp is UTC (`...Utc` suffix). Convert for display; never render a raw UTC value.
- `POST /orders` idempotency key is client-generated: create a UUID when the composer opens, keep
  it across retries, discard only on confirmation. `201 duplicate:false` and `200 duplicate:true`
  are both success.
- Staff endpoints are additive; employee endpoints are caller-scoped and cannot be reused for
  staff (`/orders/{id}` 404s on anyone else's order, deliberately).

## Stack decisions already made (§3, §10)

`dio` · `flutter_secure_storage` (never `SharedPreferences` for the token) · `local_auth` ·
`flutter_riverpod` · `go_router` · `json_serializable` + `build_runner` ·
`flutter_localizations` + `intl` with `generate: true`.

Layered `lib/` structure with a repository seam — **widgets never call the API directly**. The
directory layout is spelled out in §3.

## Theme tokens

The palette comes from the Figma design, **fixed for contrast**. The semantic colours (danger,
warning, ok) and the violet `accent` are kept from the web's `site.css`, so **the app and the web
now differ in palette** ([docs/figma-redesign.md](docs/figma-redesign.md)). Never recolour the
logo to match a theme. Keep the contrast-ratio comments on the colour constants; a palette edit
is exactly when those silently stop holding.

`AppTheme.forLocale(locale)` builds one theme per script: Cairo at 1.7 leading for Arabic, and
Inter (with Cairo as fallback) at the design's leading for English. **Never give Arabic text
letter spacing**; it breaks the joins.

The traps:
- **`iconBlue` is non-text only** (3.88:1 on the page).
- **`brandBright` never carries text on the page** (4.06:1).
- **`brandLight` is the decorative hairline** (1.18:1 on the page). Nothing a user must find may
  depend on it; interactive outlines use `outline`.
- **A chip that overrides `selectedColor` must override its label and checkmark too.** The
  theme's selected label is white, for its bright-blue fill, and white on a pale fill vanishes.
- **Exits are always faster than entrances** (§2.3).

## Standing rules

Not a workflow — these hold on every edit, whether or not a skill was invoked.

- **Never weaken a check to make something pass.** Do not delete or `skip` a failing test, loosen
  an `analysis_options.yaml` rule, add `// ignore:`, or catch-and-swallow to clear an error. Fix
  the cause, or stop and say what is blocking.
- **Never invent an endpoint, field, or status.** If it is not in [docs/contracts/](docs/contracts/)
  or the two spec documents, it does not exist. Ask rather than guess a field name.
- **Never hand-edit generated files.** `*.g.dart` and `*.freezed.dart` come from
  `dart run build_runner build --delete-conflicting-outputs`. Change the source and regenerate.
- **Never commit or push unless asked.** The one standing exception is the single commit that
  closes a phase (see *Phase workflow*), and that one is never pushed. Same for adding a dependency
  to `pubspec.yaml` — propose it first; §10 already settled the stack.
- **Back must never close the app from a screen with somewhere to go.** Landing screens
  (catalogue, queue, login, lock) confirm first via `ExitConfirmation`; pushed screens keep the
  ordinary pop. A screen reached with `go` rather than `push` has no route beneath it — give it a
  `PopScope` that routes somewhere sensible.
- **Never hardcode a colour, duration, radius or spacing value.** They live in `lib/theme/`. A
  literal in a widget is a bug even when it looks right.
- **Never read `AppLocalizations` (or any inherited widget) from `initState`.** It throws a
  framework assertion, which in a `ConsumerState` surfaces only as a screen that fails to load —
  the status screen shipped this way. Defer the first load to
  `addPostFrameCallback`, as the queue and status screens now both do.
- **A fixed `childAspectRatio` on a grid of text is a bug.** It dictates the tile *height*, so a
  label needing more room overflows instead of growing — this shipped twice, and overflowed at the
  **default** text scale on a 320dp phone, not merely at the accessibility scales. Size tiles from
  their content (`Wrap` + a measured width, or `mainAxisExtent`) and let them get taller.
  `test/features/responsive_layout_test.dart` holds every screen to 320dp at 1x/1.5x/2x in both
  locales; it catches this class of bug and nothing else does.
- **Use `AppCard` and `SectionHeader`** (`lib/shared/widgets/`) rather than rebuilding the
  surface-plus-hairline-border container or a bare `labelLarge` heading. Six copies of the card had
  accumulated; they agreed by coincidence, which is how a palette edit starts missing one.
- **Never write user-facing English into a widget.** Arabic is the primary locale; strings go
  through ARB files. Surface `ApiError.message` as-is — it arrives already localised.
- **Never log or print a token, password, or full auth header**, including while debugging.
- **State what the tests actually said.** If `flutter test` or `flutter analyze` was not run, say
  so — do not describe unverified work as done.

## How to run a task

How to work, not what to build. These follow Anthropic's Opus 5.5 guidance, fitted to this repo.

- **Keep going; stop only when blocked on me.** When a step does not need my input, take it. Put
  status notes in the same message as the next action rather than pausing to report. Stop and ask
  only when you cannot continue without a decision from me, or before anything destructive or
  outward-facing: deleting files or data, `git push`, force-pushing, rewriting history, or
  anything that hits the live API with a write. Committing and adding dependencies stay ask-first,
  as the standing rules say.
- **The finish line is `flutter analyze` clean and `flutter test` passing** unless the task names
  another. Run both before calling a code task done, and the responsive suite whenever a layout
  changed.
- **Once a question is answered, treat the answer as settled.** Do not reopen an earlier conclusion
  in a long run unless new evidence contradicts it — and then say what the evidence was.
- **Long runs keep their task list in a file** (`~/.claude/plans/<task>.md`, never inside the repo)
  and update it as each step lands, so the work survives the context being summarised.
- **Split wide work across subagents and check each result.** An audit of every screen against a
  rule, a sweep of the ARB files, or a review across `lib/` fans out well; a single screen does
  not. Read what each subagent returns before relying on it — a subagent's summary is a claim,
  not a verification.
- **Mark anything you could not confirm, and say where you looked.** This matters most for the
  backend: a behaviour read in [docs/contracts/](docs/contracts/) is not the same as one exercised
  against the server, and [docs/backend-findings.md](docs/backend-findings.md) exists because they
  differed.
- **When asked to review a diff, list only what would block the merge**, each with file and line.
  §12 of the app guide and the standing rules above are the bar; style preferences are not.
- **End every run with three headings:** **Blocked on me** (decisions left open, anything needing a
  device, credentials, or the backend repo), **Changed** (files and behaviour), **Found** (bugs,
  contradictions or backend issues noticed but not fixed). Lead with *Blocked on me*, since that is
  what I read first. Keep all three even when one is empty, and write "nothing" under it.
- **Work in phases, and close each one the same way** (below).
- **For design work, name the habits to leave out** rather than asking for "not generic": no
  recoloured logo, no violet outside "my own jar", no disabled control without a stated reason, no
  fixed-aspect text tiles, no `left`/`right`.

## Phase workflow

A **phase** is one step of a plan in `~/.claude/plans/` that leaves the app building: a
repository, a screen, a behaviour. A **milestone** is the end of a plan or of a `/buffet-feature`
run. Each phase ends with these steps, in order:

1. **Tests:** `flutter analyze` clean and `flutter test` passing, plus the responsive suite if a
   layout changed. A red result stops the phase here.
2. **Audit in a fresh context:** spawn a `general-purpose` subagent that did not write the code.
   Give it the phase's diff (`git diff` against the last phase commit), this file and
   [§12](docs/flutter-app-guide.md). Ask it to list only what would block the merge, with file and
   line, checked against the domain rules and standing rules. The author's context is exactly
   what makes a same-session review miss things, so `/buffet-feature` stage 8 does not replace
   this step. Fix every finding, then go back to step 1. If a finding is wrong, say why in the
   report rather than dropping it silently.
3. **Docs:** update whatever the phase made untrue or newly true. That means *Current state* above
   (including rules a future edit must not undo), the plan file,
   [docs/backend-findings.md](docs/backend-findings.md) if the server behaved differently from
   the contracts, and a `docs/backend-request-*.md` for anything only the backend can fix.
4. **One conventional commit:** `feat:`, `fix:`, `refactor:`, `test:` or `docs:`, with a scope
   where it helps (`feat(queue): …`), covering the code, tests and docs of that phase. Never mix
   two phases in one commit. Only commit on `feat/*` or `fix/*` branches, never on `main`, and
   never push.

At a **milestone**, also run a **definition-of-done check**: go through
[§12](docs/flutter-app-guide.md) item by item against the code as it stands. Tick only what you
verified, cite the file or test that shows it, and list what remains open under *Found*. A box
ticked on memory is how a checklist stops meaning anything.

## Commands

Once the project is scaffolded:

```bash
flutter pub get
flutter analyze
dart format .
dart run build_runner build --delete-conflicting-outputs   # after touching models
flutter test
flutter test test/path/to/file_test.dart --plain-name 'test name'   # single test
flutter run
```

## Tooling in this repo

- **`/buffet-feature`** ([.claude/skills/buffet-feature/](.claude/skills/buffet-feature/)) — the
  nine-stage pipeline for building a feature: requirements → architecture → Context7 → plan →
  implement → test → analyze → review → fix. Use it for a screen, repository, or model; skip it
  for a one-line edit or a question.
- **`dart-guard` hook** ([.claude/hooks/dart-guard.sh](.claude/hooks/dart-guard.sh), wired in
  [.claude/settings.json](.claude/settings.json)) — runs after every `Edit`/`Write` on a `.dart`
  file and flags `left`/`right`, literal `Color(0xFF…)` outside `lib/theme/`, status compared to an
  integer, a token near `SharedPreferences`, and a control disabled near stock. Advisory, not
  blocking: it surfaces feedback, so read it rather than working around it. Extend the script when
  a new mechanical rule appears — it catches what review forgets.
- **Skills worth reaching for directly:** `impeccable` and `emil-design-eng` (UI craft),
  `animate` (motion), `flutter-apply-architecture-best-practices` (the repository seam),
  `dart-run-static-analysis`, and the `flutter-add-*-test` family.
- **Context7 MCP** — call `resolve-library-id` then `query-docs` before writing against `dio`,
  `go_router`, `riverpod`, `local_auth`, or `flutter_secure_storage`. Their APIs move; do not
  write from memory.

The Dart MCP server is **not** currently installed — the `dart-*` skills fall back to CLI
commands, and `dart-fix-runtime-errors` cannot verify via hot reload. Installing
`dart-flutter@dart-flutter` from the `flutter/agent-plugins` marketplace would enable both.
