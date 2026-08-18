---
name: buffet-feature
description: End-to-end pipeline for building a feature in the Digital Buffet Flutter client — requirements, architecture check, Context7 docs lookup, plan, implement, test, analyze, review, fix. Use when asked to build, add, or implement a screen, repository, model, or feature in this app. Not for one-line edits or pure questions.
user-invocable: true
argument-hint: "[feature description, e.g. 'the order composer screen' or 'MaterialsRepository']"
---

# Building a feature in the Digital Buffet client

A nine-stage pipeline. Each stage names the skill or MCP tool that does the work, and the
project-specific rule it must not break. **Do not skip stages 2, 7, or 8** — they are where this
codebase's domain rules actually get enforced.

Read [CLAUDE.md](../../../CLAUDE.md) first if it is not already in context. The eleven domain rules
there are the acceptance criteria for stage 8.

## Stage 0 — Is the project scaffolded?

Check for `pubspec.yaml` at the repo root.

- **Absent:** the repo is docs-only. Scaffold first (`flutter create`), apply §11 platform setup
  (`FlutterFragmentActivity`, `minSdkVersion 23`, `NSFaceIDUsageDescription`), then continue.
- **Present:** proceed.

## Stage 1 — Analyze requirements

Resolve the feature against the authoritative docs, not against intuition:

- [docs/flutter-app-guide.md](../../../docs/flutter-app-guide.md) — §7 employee, §8 staff screens
- [docs/staff-api-spec.md](../../../docs/staff-api-spec.md) — endpoints and the four deviations
- [docs/contracts/](../../../docs/contracts/) — the C# wire contracts to mirror field-for-field

Write down: which endpoints, which DTOs, which of the eleven domain rules apply, and **which
states beyond the happy path** (shortage warning, `Ready`, empty catalogue, expired token, offline).

Stop and ask the user only if the docs genuinely disagree with the request. If §1.3 says the thing
should not be built at all — a staff declarations tab, a guest-order screen, a sugar name on the
queue card, any admin screen — say so now and stop.

## Stage 2 — Check architecture

Invoke `flutter-apply-architecture-best-practices`.

The seam is non-negotiable: **widgets never call the API directly.** UI → repository → api client.
Place files per §3's `lib/` layout. If the feature needs a new repository, it goes in
`data/repositories/` and the widget reads it through Riverpod.

For a UI-bearing feature also load `impeccable` (design system, hierarchy, a11y, RTL, i18n) and
`emil-design-eng` (interaction polish). For motion, `animate`. These carry the craft bar; §2's
tokens carry the brand — tokens win on any conflict.

## Stage 3 — Look up current docs (Context7 MCP)

Before writing against any package API, call `mcp__claude_ai_Context7__resolve-library-id` then
`mcp__claude_ai_Context7__query-docs`. Do this even for packages you think you know — `dio`,
`go_router`, `riverpod`, `flutter_secure_storage`, `local_auth`, `json_serializable` all move.

Query the specific thing: "dio interceptor 401 handling", "go_router redirect guard",
"local_auth authenticate options", not "how to use dio".

## Stage 4 — Create implementation plan

Produce an ordered file-by-file plan: models → repository → controller/provider → widgets → tests.
Name every file to be created or edited. For anything non-trivial, use the `Plan` agent.

State explicitly which domain rules the plan enforces and where.

## Stage 5 — Implement

Follow the plan in order. Supporting skills, invoked as they apply:

| Work | Skill |
|---|---|
| DTOs mirroring the contracts | `flutter-implement-json-serialization` |
| Routing / auth guard | `flutter-setup-declarative-routing` |
| Localisation, ARB files | `flutter-setup-localization` |
| Responsive layout | `flutter-build-responsive-layout` |
| Pattern matching over status | `dart-use-pattern-matching` |
| Widget previews | `flutter-add-widget-preview` |

Non-negotiables while writing Dart:

- Only `start`/`end` — `EdgeInsetsDirectional`, `AlignmentDirectional`. Never `left`/`right`.
- Colours from `lib/theme/`, never a literal `Color(0xFF…)`.
- Violet (`accent`) means "from my own jar" — never generic selection.
- Order status compared by **string name**, never ordinal.
- Bidi-isolate every quantity-plus-unit string.
- UTC in, local out — never render a raw `...Utc` value.
- Token to `flutter_secure_storage` only, never `SharedPreferences`.

After touching models: `dart run build_runner build --delete-conflicting-outputs`.

## Stage 6 — Run tests

`dart-add-unit-test` for logic, `flutter-add-widget-test` for widgets,
`flutter-add-integration-test` for flows, `dart-generate-test-mocks` to mock repositories.

```bash
flutter test
flutter test test/path/to/file_test.dart --plain-name 'test name'
```

Repositories test against recorded JSON. Widget-test the composer's sugar stepper (explicit 0 is
valid) and the "from my materials" toggle (visible only when an owned drink is selected).

Cover the states from stage 1, not just the happy path.

## Stage 7 — Run the analyzer

Invoke `dart-run-static-analysis`.

```bash
flutter analyze
dart format .
```

Zero errors and zero new warnings before stage 8. If layout errors appear, use
`flutter-fix-layout-issues`; for runtime stack traces, `dart-fix-runtime-errors`.

## Stage 8 — Review

Run `/code-review`, then check the diff against the domain rules a generic reviewer will miss:

- [ ] Stock deducted at `Ready`, never at `Completed`
- [ ] No control disabled on a stock reading; shortages warn only
- [ ] `warnings` array on a `200` treated as success, not failure
- [ ] Declaration wording says "awaiting confirmation", never "added"
- [ ] Status compared by name, not ordinal
- [ ] RTL verified; no `left`/`right`; units bidi-isolated
- [ ] `mustChangePassword` not skippable
- [ ] Idempotency key generated per composer session, reused on retry
- [ ] No offline order queueing
- [ ] `401` handled centrally in the interceptor
- [ ] No staff declarations tab, no guest-order screen, no admin screen
- [ ] Reduced motion honoured; targets ≥44px; text ≥4.5:1

§12 of the guide is the full checklist.

## Stage 9 — Fix issues

Apply the findings, then **re-run stages 6 and 7**. A fix that breaks a test is not a fix.

Report honestly: what was built, what the tests say, and anything left out and why.
