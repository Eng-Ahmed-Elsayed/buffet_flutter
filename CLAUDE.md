# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current state

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

Not built yet: notifications (§7.4). The `/notifications` endpoint works and matches the DTO.

**The Flutter SDK lives at `C:\src\flutter` and is not on `PATH`** — invoke it by full path
(`C:\src\flutter\bin\flutter.bat`).

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
- [docs/staff-api-spec.md](docs/staff-api-spec.md) — staff endpoints, plus the four documented
  deviations at the end.

These documents are authoritative for **meaning and behaviour**. A design (see below) is
authoritative only for layout and dimension.

## Workflow: design before Dart

Screens are designed and approved *before* widgets are written, using the `/design` skill to
produce a canvas of artboards. §1.2 names the five screens that carry the domain rules; §1.3 names
what must deliberately **not** be designed (a staff declarations tab, a sugar name on the queue
card, a guest-order screen, any admin screen).

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

Ported verbatim from the backend's `site.css` into `lib/theme/`. The palette is *sampled from the
logo gradient* — never recolour the logo to match a theme. Keep the contrast-ratio comments on the
colour constants; a palette edit is exactly when those silently stop holding. Two traps:
`accentBright` is non-text only (2.72:1), and exits are always faster than entrances (§2.3).

## Standing rules

Not a workflow — these hold on every edit, whether or not a skill was invoked.

- **Never weaken a check to make something pass.** Do not delete or `skip` a failing test, loosen
  an `analysis_options.yaml` rule, add `// ignore:`, or catch-and-swallow to clear an error. Fix
  the cause, or stop and say what is blocking.
- **Never invent an endpoint, field, or status.** If it is not in [docs/contracts/](docs/contracts/)
  or the two spec documents, it does not exist. Ask rather than guess a field name.
- **Never hand-edit generated files.** `*.g.dart` and `*.freezed.dart` come from
  `dart run build_runner build --delete-conflicting-outputs`. Change the source and regenerate.
- **Never commit or push unless asked.** Same for adding a dependency to `pubspec.yaml` — propose
  it first; §10 already settled the stack.
- **Back must never close the app from a screen with somewhere to go.** Landing screens
  (catalogue, queue, login, lock) confirm first via `ExitConfirmation`; pushed screens keep the
  ordinary pop. A screen reached with `go` rather than `push` has no route beneath it — give it a
  `PopScope` that routes somewhere sensible.
- **Never hardcode a colour, duration, radius or spacing value.** They live in `lib/theme/`. A
  literal in a widget is a bug even when it looks right.
- **Never write user-facing English into a widget.** Arabic is the primary locale; strings go
  through ARB files. Surface `ApiError.message` as-is — it arrives already localised.
- **Never log or print a token, password, or full auth header**, including while debugging.
- **State what the tests actually said.** If `flutter test` or `flutter analyze` was not run, say
  so — do not describe unverified work as done.

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
