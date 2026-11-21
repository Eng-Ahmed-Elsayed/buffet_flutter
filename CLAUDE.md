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
- Pickup vs delivery is a per-order choice, and the employee can confirm a pickup (guide §7.8).
  Deployed and verified on the live server 2026-09-27; every field stays optional in the client.

Until each phase lands, the rules below describe the app as it stands; the "Rules this redesign
changes" table in that document says which are about to move. Figma MCP is capped on the current
seat, so the design is read from the PNG exports in `design/figma/`.


**A two-repo quality pass landed on 2026-11-21**: plan and results in
[docs/quality/buffet-multi-agent-improvement-report.md](docs/quality/buffet-multi-agent-improvement-report.md)
(stocktake posting/variance fixes, signed consumption, atomic cancel reversal, staff new-order alert,
stale-poll and stale-catalogue fixes). **The SDK is Flutter 3.50.1, and the app uses the standalone
`material_ui` and `cupertino_ui` packages**: import `package:material_ui/material_ui.dart` (and
`cupertino_ui` where a Cupertino class is needed), never `package:flutter/material.dart` or
`cupertino.dart`, which are deprecated. Localisations are `AppLocalizations.delegate` plus
`...GlobalMaterialLocalizations.delegates` from `material_ui`; never `flutter_localizations`' delegates
or the generated `AppLocalizations.localizationsDelegates`, which still lists them and which
`material_ui`'s widgets do not read (`flutter_localizations` stays in pubspec only for gen-l10n).
**Every route builds its page with `materialPage(state, …)`** (`lib/app/router.dart`), never
`builder:`: go_router 14 only recognises `package:flutter`'s `MaterialApp`, and otherwise falls
back to `NoTransitionPage`, which removed every transition, Android's predictive back and the iOS
edge swipe (`test/app/router_pages_test.dart`). For the same reason the router sets
`errorPageBuilder` to the localised `NotFoundScreen` (`lib/app/not_found_screen.dart`); without it an
unknown address showed go_router's bare English error text.

**The domain rules are verified against the running server**, not just against the contracts — see
the table at the top of [docs/backend-findings.md](docs/backend-findings.md). Stock deducting at
`Ready`, shortages returning `200`-with-warnings, the `202` that creates nothing, `403` on staff
declarations, `404` (not `403`) on another user's order, and idempotency were all exercised with
the test accounts.

**Client-written Arabic is stored correctly since 2026-09-27** (an order's Arabic note and location
came back as written). Note on `Accept-Language`: earlier builds of `/auth/login` (and other API
routes) ignored `Accept-Language: en` and returned Arabic unconditionally; this has now been fixed
in the sibling `buffet_app` repo (`Program.cs` neutral `ar`/`en` cultures +
`IStringLocalizer<SharedResource>` across `EmployeeApi.cs` and `StaffApi.cs`), pending server
redeploy. **Push is switched off on the host**: `Push__ServiceAccountJson` is unset, which makes
the server drop every push silently (`Program.cs`), so no Android push arrives until it is set.

`MyMaterialDto.imageUrl` **has shipped** and works; the materials screen shows real uploaded
photographs, falling back to a category glyph when the field is null or the file 404s.

Since built: the settings screen with the language switch, **biometric unlock** (§6, with the
`locked` stage in the auth machine and all four failure modes handled), and **launcher icons** from
the peaks of the Figma logo (`design/figma/logo.png`) on white (`tool/generate_launcher_icons.py`
regenerates them, with Pillow — no `flutter_launcher_icons` dependency; the adaptive background
`ic_launcher_background.xml` mirrors its `GROUND`).

**Feature rules load with their folder.** The rules a future edit must not undo for each
feature live beside its code, and load when you work there. **Read the matching file before
editing that feature's tests**, since a test file alone does not load it:
[order](lib/features/order/CLAUDE.md) (composer, Review, Orders tab, favourites, guest mode, sugar
and extras) · [staff_queue](lib/features/staff_queue/CLAUDE.md) ·
[home](lib/features/home/CLAUDE.md) · [notifications](lib/features/notifications/CLAUDE.md) (push,
iOS gap, local alerts, background watch) · [auth](lib/features/auth/CLAUDE.md) (sign-in, forced
password, expired session, login language) · [onboarding](lib/features/onboarding/CLAUDE.md) ·
[settings](lib/features/settings/CLAUDE.md) (Account tab).

Rules for both landing screens and the app as a whole:

- **Foreground polling stays alongside push.** Push closes the closed-app gap; polling closes the
  foreground-freshness gap. They are not duplicates.
- **`prepareLandingPrompts` is called from BOTH landing screens** (`lib/app/landing_prompts.dart`).
  It is also what registers for push, so a new landing screen that skips it never gets push. It
  asks one thing at a time: the biometric offer, then the notification permission, then push
  registration. **The permission waits for the offer's sheet to finish closing**
  (`Motion.sheetExit`), not just for the answer: opened over a closing sheet, it paused the app with
  the sheet frozen on screen (seen on the emulator). A notification tap does not wait on any of it. It used to live on the composer,
  which is the *employee* landing screen — so staff, who only reach the composer by pushing it from
  the queue, had no notification channels and were never asked for permission at all. A new landing
  screen must call it.

**The Flutter SDK lives at `C:\src\flutter` and is not on `PATH`** — invoke it by full path
(`C:\src\flutter\bin\flutter.bat`).

**Employees land in a bottom-nav shell** (`lib/app/employee_shell.dart`); staff land on `/queue`.
Three navigation rules a future edit must not undo:

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

**Every digit is Latin**, dates included (`Formatters` sets `useNativeDigits = false`), and
no translation writes an Arabic-Indic one (`test/l10n/digits_test.dart`).

**Route transitions and bottom sheets stop moving under reduced motion.**
`ReducedMotionPageTransitionsBuilder` wraps Android's, Windows' and Linux's transitions, and every
`showModalBottomSheet` passes `sheetAnimationStyle: Motion.sheet(context)`. iOS keeps Cupertino's,
because bypassing it removes the edge swipe back. `test/theme/reduced_motion_test.dart`.

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

§10 settled the stack (see `pubspec.yaml`); the token lives in `flutter_secure_storage`, never
`SharedPreferences`. Propose any new dependency first.

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
