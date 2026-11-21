# Buffet improvement plan (2026-11-20)

Consolidated from three independent read-only investigations: Agent A (Flutter), Agent B (backend
operations), Agent C (independent inventory audit; did not see B's work). Where B and C reached
the same defect independently it is marked **B+C**. The orchestrator re-read the code for the P0 and the
cost sign before accepting them.

Baseline: Flutter 3.47.0 / Dart 3.13.0, analyze clean, 869 tests pass. .NET 10.0.401, EF Core
10.0.10, build 0 warnings, 460 tests pass.

## Tasks

| ID | Project | Area | Problem (verified) | Root cause | Sev | Fix | Acceptance | Tests | Owner | Deps |
|---|---|---|---|---|---|---|---|---|---|---|
| S1 | ASP.NET | Stocktake posting | Drinks served after a line was counted are added back to stock (B-01 + C-05) | `delta = counted − live at posting` (StocktakeService.cs:304) | P0 | Store `SystemQtyAtCount` when the line is saved (live balance read in the same transaction); post `delta = counted − SystemQtyAtCount`; legacy lines fall back to ledger `BalanceAfter` at `CountedAtUtc` | Snapshot 100, count 98, serve 5, post → balance 93, delta −2 | Rewrite drift test; count-then-serve; serve-then-count | B | — |
| S2 | ASP.NET | Variance | Review and report measure against the snapshot taken at open, giving false shortages (B-02 + C-06) | `Variance = counted − SystemQty` | P1 | Variance, tolerance and report use `SystemQtyAtCount` | Serve 5 before the count, count 95 → variance 0, absent from report | VarianceReportTests, posting tests | B | S1 |
| S3 | ASP.NET | Stocktake concurrency | Concurrent posts both succeed and overwrite the audit; a save can race a post (B-05 + C-15) | No lock on the document row | P1 | `UPDLOCK` on the stocktake row in Post and SaveLine inside a transaction; SaveLine re-checks status | Two parallel posts → one success, one Posted event; save after post refused | SQL concurrency tests | B | S1 |
| S4 | ASP.NET | Count entry | `1,500` saved as 1.5 (B-06) | JS `replace(',', '.')` | P1 | Strict parse server- and client-side; Arabic-Indic digits and `٫` accepted; ambiguous comma refused | `"1,500"` → validation error; `"١٢٫٥"` → 12.5 | Controller test | B | — |
| S5 | ASP.NET | Review | Reason can only be entered back on the count screen; Recount clears the count (B-12); a save wipes the reason (B-11) | Missing endpoint; unconditional overwrite | P2 | Inline reason/note on Review via a reason-only POST; missing fields mean unchanged | Setting reason at review keeps `CountedQty` | Controller test | B | S1 |
| S6 | ASP.NET | Count entry | Only base units (B-07) | — | P2 | Optional packages + loose units per row, computed server-side | 3 packets + 40 at 100/packet → 340 | Controller test | B | S4 |
| R1 | ASP.NET | Consumption cost | A cancel after Ready costs the drink 3 times; a reversal in a later window shows as consumption (B-03 + C-01/C-02) | `Value` uses Abs; `Consumed` uses Abs of the sum | P1 | Signed sums for OrderCompleted quantity and cost | Serve + cancel same day → cost 0, waste 0.50; split window → day 2 consumed −1 | ReportingServiceTests | B | — |
| R2 | ASP.NET | Cancel after Ready | Reversal recomputed from today's recipe, in a separate transaction; stale `wasted` read lets a cancel race a serve (B-15 + C-03/C-04/C-11) | Re-runs `Plan()`; flag read before CAS; duplicated in StaffController and StaffApi | P1 | One Core path: negate the order's own ledger rows (by OrderId) after the status swap, decided on the post-swap state; `ReleaseClaim` guarded by expected status | Recipe changed before cancel → reversal equals original rows; cancel racing serve still reverses | Service + SQL tests | B | R1 |
| R3 | ASP.NET | Order reports | Ready-but-uncollected orders missing; orders dated by handover (B-04 + C-08) | Filter on `HandledAtUtc` | P1 | Served window filtered on `ReadyAtUtc` for Ready/Completed | Order Ready today appears in ByEmployee | Repository test | B | — |
| R4 | ASP.NET | Day boundaries | Dashboard, history, audit and stocktake list use UTC days (B-14, C-16) | Ad-hoc `DateTime.UtcNow.Date` | P2 | Shared reporting-clock helper used everywhere | 01:30 local lands on the local day | Unit test | B | — |
| R5 | ASP.NET | Labels | "Consumption" is theoretical usage only; stocktake/manual adjustments appear in no report (C, §4) | — | P2 | Label the report as recorded (recipe-based) consumption and add a stocktake-adjustment column so the unexplained residual is visible; no physical-consumption figure invented | Report shows the stocktake delta per item for the window | ReportingServiceTests | B | S1 |
| I1 | ASP.NET | Restock / write-off | Double submit doubles stock (B-13 + C-12) | No form token | P2 | One-time submission token on both forms | Same token twice → one movement | Controller test | B | — |
| F1 | Flutter | Queue | Stale poll re-adds a served card (A-02) | Unsequenced refresh | P2 | Refresh generation; drop responses started before the latest mutation answered | Completer test: served card never reappears | queue_serve_test | A | — |
| F2 | Flutter | Composer/Home | Failed catalogue refresh replaces Review with an error (A-01) | `when` without `skipError` | P2 | `skipError` + "Couldn't refresh" banner | Review and Place order survive a failed refresh | New widget test | A | — |
| F3 | Flutter | Composer | Delivery location forgotten every order (A-04) | Not persisted | P2 | Persist and restore if still listed; clear on sign-out | Second composer preselects | composer_journeys_test | A | — |
| F4 | Flutter | Robustness | ref after await (A-07), 5xx called "network" (A-09), unknown status → Pending (A-10), history silently capped at 20 (A-14) | — | P3 | As described in Agent A report | One test each | — | A | — |
| F5 | Flutter | Evidence | Screenshot captures dated 2026-09-27, stale (A-06) | Not regenerated | P3 | Regenerate with `--update-goldens` and review | Captures dated today | capture_test | A | F1–F4 |

## Deferred, with reasons
- **Flutter 3.47.0 → 3.47.9 hotfix**: recommended (libpng security fix). The SDK at `C:\src\flutter` is shared machine state outside the repo, so it waits on the owner.
- **3.50 / riverpod 3 / go_router 18 / secure_storage 11 / local_auth 3**: each changes behaviour (riverpod 3 pauses Home's chime listener; secure_storage migration can log users out) and needs a device. Separate phase.
- **A-03 staff new-order alert + wakelock**: product decision and possibly a new dependency.
- **B-08 Partial scope / Full completeness, B-16 unit change guard, C-07 time zone, C-10 import re-credit, C-13 sugar unit, C-14 company ingredients for own-jar drinks**: need business decisions (listed in the final report).
- **A-08, A-12, A-13**: need backend contract changes; not in this pass.
