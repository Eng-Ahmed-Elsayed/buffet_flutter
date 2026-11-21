# Buffet multi-agent improvement report (2026-11-20)

Scope: `buffet_flutter` (branch `feat/figma-redesign`) and `buffet_app` (branch
`feat/redesign-backend-requests`). Nothing is committed or pushed. No live-server write was made.
The plan this report closes is [buffet-improvement-plan.md](buffet-improvement-plan.md).

How the work was run: three read-only investigators (A Flutter, B backend operations, C an
independent inventory auditor who never saw B's work), then A and B implementing in their own
repository only, then fresh-context reviewers who had not written the code, then fix rounds until
the reviewers found nothing blocking. The orchestrator re-read the code for every P0/P1 claim,
re-ran both suites itself, and drove the admin stocktake flow in a browser.

## A. Executive summary

- **The most important defect was in stocktaking, and it is fixed.** Posting a count measured
  against the balance *at posting*, so every drink served between counting a line and posting the
  count was silently added back to stock (P0). B and C found it independently; an existing test
  asserted the wrong behaviour. Expected stock is now the balance at the moment each line was
  counted, captured in the same transaction as the count.
- **Reports now reconcile.** A cancel after Ready was costed three times; a reversal in a later
  window showed as consumption; uncollected Ready orders were missing from the order reports; day
  boundaries outside the Reports pages were UTC. All fixed and tested with deterministic cases.
- **Cancel after Ready reverses what was actually deducted**, from the order's own ledger rows, in
  one service shared by the web and the API, and a failed reversal can be finished by a retry.
- **Flutter had no P0/P1.** Four P2s were fixed (a served queue card could come back; a failed
  menu refresh replaced an order in progress with an error; the delivery location was forgotten
  each order; 5xx errors were worded as connection failures).
- **Can the system replace manual stocktaking?** The arithmetic and data-integrity controls are now
  sound for counting while the buffet keeps serving, and counting in packages is supported. Three
  business decisions remain before it is a full replacement (section I): whether a Full count must
  be complete before posting, whether a second approver is needed above a value, and the
  reporting time zone.

## B. Flutter assessment

| | Before | After |
|---|---|---|
| Flutter / Dart | 3.47.0 / 3.13.0 | **3.50.1** (owner upgraded the SDK on 2026-11-20) |
| `flutter analyze` | clean | clean on 3.47.0; on 3.50.1, **163 `deprecated_member_use` infos** from the SDK's `material.dart`/`cupertino.dart` deprecation, none from this work |
| `flutter test` | 869 passed | **892 passed** |

**Decision (owner, 2026-11-21): stay on 3.50.** It is the first stable release built for Xcode 27 /
iOS 27, which fixes intermittent launch crashes on iOS 27 devices and the first-run white screen on
newly paired iPhones. It also moves iOS builds to Swift Package Manager ahead of CocoaPods trunk
going read-only in December 2026. iOS testing has not started yet (no Mac), so this is the cheapest
time. The `material_ui`/`cupertino_ui` migration is the next phase, with its two new dependencies
approved.

**Version position.** Latest stable on 2026-11-20 is 3.50.1 / Dart 3.14.0. The installed 3.47.0
misses nine hotfixes (3.47.1–3.47.9), including a libpng security fix and an Android PowerVR
Impeller fix. **Recommended: 3.47.9 now; not done** because the SDK at `C:\src\flutter` is shared
machine state outside the repository. 3.50 deprecates `material.dart`/`cupertino.dart` in favour of
new packages and reorganises page transitions; it should be its own phase.

**Dependencies (none changed).** Majors available for riverpod 3, go_router 18,
flutter_secure_storage 11, local_auth 3, Firebase, flutter_local_notifications 23. Deliberately
not upgraded: riverpod 3 pauses listeners in invisible widgets, which would silently stop Home's
order chime; secure_storage 11 migrates the key store and, without `migrateWithBackup`, can sign
every user out; local_auth 3 remaps the four lock failure modes. Each needs a device test.

**Implemented**

| ID | Change | Test |
|---|---|---|
| F1 | Queue drops a refresh that started before the latest action answered, so a served or handed-over card never reappears; a failed handover refreshes at once | `queue_stale_poll_test.dart` (3 cases, verified failing without the fix) |
| F2 | A failed catalogue refresh keeps Home and every composer step (incl. Review) on screen with "Couldn't refresh" + Retry | `composer_journeys_test.dart`, `home_screen_test.dart` |
| F3 | Delivery location remembered, restored only if still listed, cleared on sign-out | `composer_journeys_test.dart`, `preferences_location_test.dart` |
| F4 | `mounted` guards on the status screen; 5xx without a message → generic error, not "network"; unknown status gets no actions; order history asks for 100 (server cap, checked) | `api_hardening_test.dart`, `order_tracking_test.dart` |
| F5 | 78 screenshot captures regenerated (the old ones pre-dated four phases) | `test/screenshots` |

| A-03 | Staff queue alerts once per refresh that brings new orders (sound on a `new_order` channel + vibration); never on first load, on the resume catch-up, or for this device's own order; on/off switch in staff settings (default on). No keep-awake (owner decision) | `queue_new_order_alert_test.dart` (6) |

**Outstanding:** a duplicate-key response is shown as a plain success; declarations have no
idempotency key; `LocationDto` has no English name (the last two need the backend).

## C. Stocktaking assessment

**Process (as built):** Admin opens a sheet for one owner (buffet stock or one employee) → the
active items' balances are snapshotted → lines are counted with autosave (blank = not counted,
0 = counted empty; blind count optional) → Review shows variance, tolerance (2% default) and money
impact → lines over tolerance need a reason → Post writes one ledger row per line with a variance,
in one transaction → the document is immutable; a correction is a new count.

**Problems found and fixed**

| ID | Problem | Fix | Evidence |
|---|---|---|---|
| S1 (P0) | Posting re-added stock served after a line was counted | `SystemQtyAtCount` captured with the count; delta = counted − that | `Reconciliation_Snapshot100Count98Serve5Post_Lands93`, `ServingAfterTheCountIsKeptWhenPosting` |
| S2 | Variance and tolerance measured from the opening snapshot → false shortages | Variance, tolerance (numerator and denominator), list and report use the count-time balance | `ServingBeforeTheCountIsNotAVariance`, `Tolerance_UsesTheCountTimeBalanceAsTheDenominator` |
| D1 (review) | A legacy line re-saved on blur took today's balance | Same-figure re-save of a legacy line fills from the ledger at its original count time | `LegacyLineReSavedWithTheSameFigureAfterServesStillPostsFromTheLedger` |
| S3 | Two concurrent posts both succeeded and overwrote the audit | Document row read `WITH (UPDLOCK, HOLDLOCK)` in Save/Post/Cancel; Save re-checks status | `ConcurrentPostsProduceOneSuccessAndOnePostedEvent`, `SavingALineAfterPostingIsRefused` |
| S4 | `1,500` was saved as 1.5 | Strict parser (Latin/Arabic-Indic digits, `.`/`٫`, any comma refused) on server and client | `CountQuantityParserTests`, two screen tests; seen refused in the browser |
| S5 | A reason could only be set on the count screen; a save could wipe it | Reason/note editable on Review; saves change only the fields sent | `SetReason_AtReviewKeepsTheCount` |
| S6 | Counting only in spoons/grams | Optional packages + loose units, computed on the server | `Autosave_ConvertsPackagesPlusLooseUnitsOnTheServer`; 4 bags + 37 = 437 in the browser |
| N1 | (pre-existing, live today) A stocktake could not be opened with Notes empty; the button silently did nothing | Implicit `[Required]` on non-nullable strings switched off app-wide; Users/Edit normalises its four optional names (the switch first exposed them as a 500) | `OpeningACountWithNoNotesRedirectsToTheCount`, `R3_*` tests; seen working in the browser |
| N4/P2 | Typing packages saved an interim value; tabbing past an empty line logged an event | The pair saves once; untouched blank lines send nothing | Browser: one save of 438; no save on tab-through |

**Data-integrity controls now in place:** count-time expected balance; document-row update lock;
unique index on the ledger's stocktake line id (no double posting); immutable posted documents;
event trail per document plus the audit log.

**Usability, from driving it in a browser:** open → count → review → post took one screen each, with
progress, search and category filter; Post stays disabled with the reason stated until every
breaching line has a reason; the confirmation states the number of adjustments and the net value.

## D. Inventory and consumption model

Derived by Agent C from code and confirmed by the reviewers.

- Stock is held per `(ItemId, OwnerUsername)`, owner `""` = buffet stock, an email = an employee's
  own jar, in base units. Every change goes through one repository method that locks the balance
  row and writes a ledger row with `BalanceAfter` and `UnitCostAtTime`. Replaying an owner's ledger
  reproduces the balance (`StockLedgerConsistencyTests`).
- Movements: `InitialStock` (+), `Restock` (+), `OrderCompleted` (− at Ready; + on reversal),
  `Waste`/`Expired` (−), `ManualAdjustment` (− only, write-off "Other"), `Stocktake` (±),
  `PersonalDeposit` (+, on a confirmed declaration). Completed writes nothing. There are no
  transfers or locations; the owner is the only partition, and it is resolved on the server.
- **Closing stock** = opening + InitialStock + Restock + PersonalDeposit − consumption − waste/expired
  − manual adjustment ± stocktake.
- **Theoretical (recorded) consumption** = −Σ `OrderCompleted` deltas, from recipes at Ready. The
  report now says so ("Recorded item consumption").
- **Physical consumption** is not computed: it needs a full count at both ends of the period. The
  "Stocktake adjustments" column now shows the residual between the books and the shelf, which is
  the input a physical figure would use. No physical figure is invented.
- **Variance** = counted − balance at count time; value = variance × unit cost at snapshot.

**Deterministic cases (expected = actual, all by test or browser)**

| Case | Expected | Result |
|---|---|---|
| Snapshot 100, count 98, serve 5, post | balance 93, Stocktake −2 | pass |
| Snapshot 100, serve 5, count 95, post | no row, variance 0, not in report | pass |
| Count 98, 3 served, recount 96 | count-time 97, delta −1, balance 96 | pass (reviewer) |
| Count 98, restock 50, post | delta −2, balance 148 | pass (reviewer) |
| Tea 0.50 serve + cancel same day | cost 0.00, waste 0.50 | pass |
| Serve day 1, cancel day 2 | day 2: consumed −1, cost −0.50 | pass |
| Recipe changed between Ready and cancel | reversal equals the original rows | pass |
| Cancel whose reversal failed, then retried | reversed once; later cancels write nothing | pass |
| Sugar 500, count 4 bags + 37 spoons, post | −63, value −31.50, balance 437, report shows −63 | pass (browser) |

**Known limitations:** recipe versions are not stored per order (the cancel fix avoids needing
them); sugar deducts one base unit per spoon whatever the item's unit; own-jar drinks draw company
recipe ingredients with no limit; deactivated items cannot be counted.

## E. Reporting assessment

| Report | Source | Change | Verification |
|---|---|---|---|
| Recorded consumption (+ Excel) | Ledger, all owners | Signed quantity and cost; stocktake-adjustment columns; export has the screen's totals row; bar widths clamp at 0 | ReportingServiceTests, BarChartTests, browser |
| Variance | Posted company stocktakes | Uses the count-time balance, so it agrees with the posted ledger rows | VarianceReportTests |
| By employee / department / preferences | Orders | Served window filtered on `ReadyAtUtc` (Ready or Completed), matching when stock left the shelf | `ServedWindow_IncludesAnOrderMadeButNotCollected` |
| Dashboard, item history, audit, stocktake list | various | One `ReportingClock` for every day boundary | Clock tests |

Not changed: peak hours/days still bucket on creation time while the window is Ready time (P3).
The configured zone is still `Arab Standard Time` (UTC+3, no DST); see section I.

## F. UX assessment

- **Mobile (employee):** ordering keeps its state through a failed refresh; the location is
  remembered; errors say what happened. Remaining: a staff queue card for two drinks is ~680dp
  tall, so in a rush staff see one order per screen (worth a design pass).
- **Admin:** stocktake counting in packages, inline reasons, an immediate "Saved — 437 spoon"
  echo, and a refusal of ambiguous numbers. A restock or write-off submitted twice now moves stock
  once.
- **Staff web:** the cancel path is now one service; no visible change.
- **Customer-facing:** the employee web and app are the customer surface; covered above.

## G. Independent review results

| Reviewer | Scope | Findings | Outcome |
|---|---|---|---|
| Reviewer A (fresh) | Flutter diff | 2 × P3 | 1 fixed (handover refresh); 1 wrong (`/start` already refreshes, `queue_screen.dart:567`) |
| Reviewer B (fresh) | Backend business correctness, with its own tests | D1 P1, D2 P2 (both reproduced), D3, D4 P2, D5 P3; NU1902/1903 on restore | All fixed; Pkcs pinned 9.0.21 |
| Re-auditor (fresh) | D1–D5 | All verified; 6 adversarial tests pass; 3 minor | M1 (a false "nothing was recorded" after a restart, which invited a double restock), M2, M3 fixed; migration matches the model |
| Orchestrator browser pass 1 | Admin stocktake + report, EN and AR | N1 (pre-existing P1), N2–N5 P3 | All fixed |
| Round-3 reviewer (fresh) | Global validation switch, test change, N2–N5, M1–M2 | **Users/Edit returned 500 on a blank optional name** (reproduced); everything else verified, incl. 902 matching resx keys | Fixed; the reviewer's 6 tests ported into the suite |
| Orchestrator browser pass 2 | Same, plus 360dp | Arabic-Indic digits in save echo, stray event, cramped phone row, sign placement | All fixed and re-checked in the browser at 360dp |

| Owner-decision reviewer (fresh) | Staff alert, Egypt zone, Full-count acknowledgement | None blocking; 3 low notes (below) | Recorded as follow-ups |

Final state: no known P0 or P1 open in either repository.

Low-severity follow-ups from the last review, not fixed:
- The acknowledgement accepts a number at least equal to the uncounted lines, not exactly equal;
  a stale smaller number is refused, which is the direction that matters.
- The acknowledgement is checked just before the posting transaction, not inside it; a line
  uncounted in that window posts with one more uncounted line than acknowledged (no stock effect).
- If the silent catch-up refresh after a resume is dropped as stale, the next poll can buzz once
  for orders already on screen.
- The `new_order` notification channel is also created on employee devices (never fires there).
- Egypt zone resolution verified on Windows only; a Linux host without tzdata would fall back to UTC.

Agent B rewrote two tests because they asserted the P0 behaviour
(`DriftBetweenSnapshotAndPostingIsSurfacedNotSilentlyAbsorbed`,
`PlanPosting_LandsTheBalanceOnTheCountedFigureDespiteDrift`); the orchestrator accepted both. No
test was deleted or skipped.

## H. Final test results

| | Baseline | Final |
|---|---|---|
| Flutter analyze | clean | clean |
| Flutter tests | 869 | 892 (SDK 3.50.1) |
| Flutter analyze | clean | 163 SDK deprecation infos on 3.50.1 (migration is the next phase) |
| .NET build | 0 warnings | 0 warnings, 0 errors |
| .NET tests | 460 | **537 passed**, 0 skipped (LocalDB tests ran) |
| Vulnerable packages | not checked; a clean restore failed on NU1902/NU1903 | none; `System.Security.Cryptography.Pkcs` pinned to 9.0.21 |
| Browser (admin web, LocalDB) | none | stocktake create → count → review → post → report, EN + AR, desktop + 360dp |

All final figures above were produced by the orchestrator's own runs, not taken from agent reports.
JavaScript and CSS changes (count entry) have no automated test harness; they were verified by hand
in the browser only.

## I. Remaining blockers and next steps

**Decided by the owner on 2026-11-20 and implemented**
- Reporting time zone is Egypt (`Egypt Standard Time`, DST handled; tests for winter and summer).
  **Deploy:** if the host sets `BuffetStore__ReportingTimeZone`, change it there too.
- A Full stocktake with uncounted lines warns, lists them, and needs an explicit acknowledgement
  (enforced on the server); uncounted lines stay unchanged. Verified in the browser in Arabic at 360dp.
- Staff new-order alert: sound + vibration, no keep-awake.

**Business decisions still open**
1. Partial/Spot stocktakes are still labels with no item picker.
2. Second approver for postings above a value?
4. Should uncollected Ready orders expire or auto-complete?
5. Changing an item's unit or package size while it holds stock: forbid or convert?
6. Sugar unit policy; company ingredients consumed by own-jar drinks.
7. Should restock record a supplier and purchase cost (today unit cost is a static item field)?

**External / infrastructure**
- `appsettings.Development.json` points at the **live** database and the app migrates on start:
  running locally without an override would apply this branch's migration to production.
- Flutter SDK 3.47.9 hotfix (owner's machine).
- Push is still off on the host (`Push__ServiceAccountJson` unset). The service-account key held in
  the developer's user-secrets was printed into this session's transcript; rotate it.
- Redeploy needed for the backend changes; the new migration adds one nullable column.

**Code follow-ups (P3, not done)**
- Peak hours/days bucket on creation time while the window filters on Ready time.
- Admin form validation now relies on explicit checks; a new entity-bound form must normalise its
  optional strings (Users/Edit is the precedent).
- Count rows at 360dp scroll horizontally inside their table to reach the status column.
- The repository has no JavaScript test harness; the count script is verified by hand only.

**Additional testing needed**
- Real device: Flutter changes were verified by widget tests only.
- Concurrent posting was tested in LocalDB, not on the shared host.
- Submission tokens are in memory; a multi-instance deployment needs shared storage.
