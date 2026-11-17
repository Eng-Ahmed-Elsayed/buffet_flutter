# Independent verification of the Antigravity audit changes

Date: 2026-11-17. Scope: the uncommitted changes in `buffet_flutter` (`feat/figma-redesign`) and
`buffet_app` (`feat/redesign-backend-requests`). Nothing was committed or pushed. The live server
was not touched. Every database test ran against throwaway LocalDB databases.

## Executive verdict: VERIFIED WITH LIMITATIONS

The previous agent's changes are sound on the whole, but **three defects were confirmed and are now
fixed**, two of them P1:

- **P1.** Confirming a material declaration could lose the stock for good. It is now one
  transaction.
- **P1.** The admin *Users → Import* screen deactivated every user whose «مفعّل» cell was left
  blank.
- **P2.** The Drink Details sugar chips showed a sugar as chosen even when no sugar was being sent.

One more import defect, older than this work, was fixed alongside the second one.

**No P0 or P1 defect remains open in the verified scope.** "With limitations" covers the
following:

- No live end-to-end run against a deployed server.
- No device runs.
- No iOS build.
- The store-console and legal items, which need people rather than code.

Evidence levels used below:

| Level | Meaning |
|---|---|
| **Code** | Inspection only. |
| **Unit/Widget** | Flutter tests with providers overridden. These are mocked, not integration. |
| **DB-integration** | .NET tests against a real SQL Server (LocalDB) through the real repository. |
| **HTTP-integration** | The ASP.NET app booted through `WebApplicationFactory`, over real HTTP and cookie auth, against LocalDB. |
| **E2E** | Flutter → live API → database. **Not performed in this pass.** |

---

## 1. Previous fixes verification

| Previous fix | Files inspected | Method | Result | Remaining concern |
|---|---|---|---|---|
| `CatalogueResponse.availableItemIds` (drinks + sugars + extras) | catalogue_models.dart, home, favourites_screen, choose_drink_step, favourite_models_test | Code + Unit | VERIFIED | A favourite with a retired extra or sugar is now *marked* unavailable in the strip. On replay the extra is dropped without a notice naming it (see N-5). |
| `sortOrder` on `CatalogueItemDto` | catalogue_models(.g).dart, ApiContracts.cs, EmployeeApi.cs | Code | VERIFIED | `defaultValue: 0` keeps older servers parsing. The client does not re-sort, which is correct because the server already sends menu order. |
| `applyFavourite` filtering of retired and unowned extras | composer_controller.dart, composer_controller_test | Code + Unit | VERIFIED | The `composed == null` branch can never be taken (`_asLine` never returns null). This is dead code, not a bug. |
| Variant fallback `firstOrNull` | composer_controller.dart:530 | Code | VERIFIED | Matches the server's `ResolveVariant` (`IsDefault ?? variants[0]`). |
| Notes cleared after confirmation | composer_screen.dart:475 | Code | VERIFIED | Cleared only in the confirmed branch, beside `resetAfterConfirmedOrder`. A failed placement keeps the notes. |
| Retired-drink notice fallback | composer_screen.dart:701 | Code | VERIFIED | The server now fills `drinkNameAr` on favourites as well, so the fallback is a second safety net. |
| Composer back fallback to `Routes.home` | composer_screen.dart:251 | Code | VERIFIED | A staff user is redirected from `/home` to `/queue` by `signedInRedirect`. No second shell is stacked, because `go` replaces the stack. |
| Multi-sugar chips | drink_details_step.dart, server `ResolveSugar` | Code + Widget | **FAILED → fixed (N-3)** | The server zeroes the spoons when two or more sugars are active and none is named, so the feature is necessary. The chip's selected state was wrong. A private sugar is not painted violet (open, N-6). |
| Image URL normalisation and `ExcludeSemantics` | item_image.dart, api_config.dart | Code | VERIFIED | `imageUrl` returns an absolute URL unchanged, so the double call in My materials is harmless. Every image sits beside its text name, so it is decorative and excluding it from semantics is correct. |
| Notifications `_markedRead` and empty-unread guard | notifications_screen.dart | Code | VERIFIED WITH LIMITATIONS | A failed *load* throws before the flag is set, so Retry still works. A failed *mark-all-read* is swallowed, as it was before. The badge can stay stale until the next open. This is not a regression. |
| Queue `paused`/`hidden` → `_commitPendingMounted` | queue_screen.dart:135-196, 345 | Code | VERIFIED | `_commit` removes the pending entry synchronously, so the `hidden`→`paused` pair cannot send twice. The card leaves at once and `_serving` filters it from polls. The `complete` branch can never run, because `PendingActionKind.complete` is never created. A killed process still loses the send (documented, unfixable on device). |
| Shortage banner `Formatters.isolate` | queue_screen.dart:716, home greeting, review guest name | Code | VERIFIED | Not checked in rendered RTL output in this pass. |
| AR/EN delivery strings | app_ar.arb, app_en.arb | Code | VERIFIED | The wording now matches the location dropdown. |
| `PrivacyInfo.xcprivacy` | ios/Runner, project.pbxproj | Code | **NOT VERIFIED / FAIL as shipped** | The file is **not referenced by `project.pbxproj`**, so it is not in the bundle. Its contents are also inaccurate (see §6). |
| `ITSAppUsesNonExemptEncryption=false` | Info.plist | Code | VERIFIED | The app uses only HTTPS and Keychain. |
| `FirebaseAppDelegateProxyEnabled=false` | Info.plist, main.dart, push_controller.dart, firebase_options.dart | Code | VERIFIED (today) | Firebase is never initialised on iOS: `PushController.isSupported` is Android-only and `firebase_options` throws for iOS. When APNs is added, the APNs token and notification delegate must be wired by hand (§7). |
| Localised Face ID text | Info.plist, *.lproj/InfoPlist.strings | Code | VERIFIED WITH LIMITATIONS | The `.lproj` files are also not in `project.pbxproj`. Until then the Arabic base string in Info.plist is what iOS shows. |
| Android `allowBackup=false` | AndroidManifest.xml | Code | VERIFIED | Right for `flutter_secure_storage`: Keystore keys are not restored, so a restored cipher store would fail to decrypt. |
| FCM default channel `order_ready` | AndroidManifest.xml, order_alerts.dart:22 | Code | VERIFIED | The channel is created with that id. |
| Neutral `ar`/`en` cultures and localised API errors | Program.cs, EmployeeApi.cs, StaffApi.cs, *.resx | Code (reviewer) + HTTP-integration (existing parity tests) | VERIFIED WITH LIMITATIONS | Every referenced key exists in both resx files. Not redeployed, so the live `/auth/login` still answers in Arabic. |
| Inactive items and wrong categories rejected | OrderService.cs:198-206, 492 | Code + DB-integration (`InactiveItemsAndWrongCategoryItemsAreRejected`) | VERIFIED | |
| Arabic snapshots (`NameAr`, not `DisplayName`) | OrderService.cs:475-499, InventoryItem.DisplayName | Code + DB-integration | VERIFIED | `DisplayName` depends on the culture, so an English request stored English text in `DrinkNameAr`. Rows already written that way are not repaired, and no migration exists for them. |
| Private-item source resolution | OrderService.cs:552-561 | Code | VERIFIED | `GetItemsForAsync` returns only company items plus the caller's own private items. A private item has no company balance, so charging it to Company was wrong. No dedicated test was added. |
| Concurrency token on `OrderHeader.Status` | BuffetDbContext.cs:329, SqlBuffetRepository.cs:684-737 | Code | VERIFIED | `UpdateOrderStatusAsync` turns a lost race into `false`, which is the existing "already moved" path. `ReleaseClaimAsync` can now throw on a race, but only inside a failure-recovery path. No schema change is needed, because a token alone adds a `WHERE` clause. |
| Concurrency token on declarations and claim-first confirm | PersonalStockService.cs, SqlBuffetRepository.cs | Code + DB-integration | **FAILED → fixed (N-1)** | |
| Non-company stocktake snapshot cost = 0 | SqlBuffetRepository.cs:1200 | Code | VERIFIED | Personal stock has no company cost. |
| `/orders/mine` limit pushed into the query | EmployeeApi.cs:416, SqlBuffetRepository.cs:654-659 | Code + HTTP-integration (parity test) | VERIFIED | `Take` comes after `OrderBy CreatedAtUtc desc, OrderId desc`, so ordering is stable. The cap is 100 and the default is 20. This is a limit, not paging. |
| Favourite `drinkNameAr` from the deleted-item-inclusive lookup | EmployeeApi.cs:577-620 | Code + HTTP-integration | VERIFIED WITH LIMITATIONS | It exposes only the names of items the user had already saved. It loads every item on each `GET /favourites`, which is fine at this catalogue size. |
| Stocktake confirm attributes | Count.cshtml, Review.cshtml, confirm-dialog.js | Code (reviewer) | VERIFIED | Before this, the confirm sat on the buttons and was ignored, so Cancel and Post had no confirmation at all. Antiforgery tokens are intact. |
| Excel header aliases and absent-`IsActive` handling | UsersController.cs, TemplatesController.cs, SheetMap.cs | Code + HTTP-integration | **FAILED → fixed (N-2)** | |
| `CanOrderForGuests` import | TemplatesController.cs | Code | VERIFIED | It used to be revoked on every template import, and now keeps the existing value when the column is absent. A blank cell means "no", which the template says. |
| Location audit, inventory feedback, audit filters, declaration history, admin navigation | Controllers and views | Code (reviewer) | VERIFIED | Not looked at in a browser. |
| Variance report scoped to company stock | ReportsController.cs, `GetPostedStocktakesAsync` | Code (reviewer) | VERIFIED | It filters on owner `""`, and the export goes through the same builder. |
| `_BarChart` RTL/LTR coordinates | _BarChart.cshtml | Code (reviewer, arithmetic checked) | VERIFIED | Not looked at in a browser. |

## 2. New issues discovered

| ID | Sev | Area | Problem | Root cause | Status |
|---|---|---|---|---|---|
| N-1 | **P1** | Backend, personal stock | `ConfirmAsync` marked the declaration Confirmed and only then credited the stock, in a separate call. Any failure between the two left a declaration that credited nothing. It disappears from every confirm screen and can never be confirmed again, so the employee's jar is lost without a trace. | The previous agent reversed a deliberate fail-safe ordering to stop a double credit. Either order of two separate writes loses something. | **Fixed** |
| N-2 | **P1** | Admin, Excel | `/Users/Import` with the «مفعّل» column present but blank deactivated existing users and created new ones inactive. That is a lockout. The template upload with no «مفعّل» column re-enabled suspended accounts. | `SheetMap.GetBool` returns false for an empty cell. The template path defaulted to `true` instead of the existing value (this one predates the diff). | **Fixed** |
| N-3 | P2 | Flutter, Drink Details | The sugar chip showed `sugarItemId ?? sugars.first` as selected. For a replayed favourite with spoons but no sugar, or a retired one, the UI promised a sugar the order omitted, and the server then dropped the spoons. | The selection was computed with a fallback instead of from state. | **Fixed** |
| N-4 | P3 | Admin, Excel | A sheet with no Role column, or an empty role, makes existing Admin and Staff accounts Employees. | The fallback is `Employee`, not the existing role. Predates the diff. | Open. The business needs to say whether a missing role means "keep". |
| N-5 | P3 | Flutter, favourites | Replaying a favourite drops a retired extra without naming it. CLAUDE.md says what does not fit "is named in a notice". | `applyFavourite` reports only retired *drinks*. | Open. Needs a notice string, an ARB entry and approval. |
| N-6 | P3 | Flutter + backend | A *private* sugar in the catalogue is drawn from the owner's jar on the server, but its chip is not violet (rule 3). | "No sugar jar toggle" was decided before the sugar chips existed. | Open. A design decision. |
| N-7 | P3 | Backend test | The new `/orders/mine` parity test never checks the status of its two `POST /orders`, so a refused placement shows up as "expected 1, found 0". | Test hygiene. | Open |
| N-8 | P3 | iOS | `PrivacyInfo.xcprivacy` is not in the target and its declarations are inaccurate (§6). | No Xcode available to add it. | Open. Needs macOS. |

## 3. Fixes implemented

**N-1: confirm is one transaction.** `buffet_app`:

- `IBuffetRepository.ConfirmDeclarationAsync` (new)
- `SqlBuffetRepository.ConfirmDeclarationAsync`
- `PersonalStockService.ConfirmAsync`

The repository now does three things inside one transaction, under the execution strategy:

1. Re-reads the declaration and requires it to be Pending.
2. Stages it as Confirmed, stages the credit through `AppendMovementsAsync` (the same
   `UPDLOCK, HOLDLOCK` balance discipline), and publishes the item.
3. Saves. The `Status` concurrency token turns a lost race into a rollback and `false`.

This mirrors `PostStocktakeAsync`, which exists for the same reason.

Regression tests, in `PersonalStockServiceTests`, against LocalDB:

- `ConfirmingConcurrently_CreditsTheStockExactlyOnce`: six connections confirm at once. Exactly one
  returns true, there is one ledger row, and the balance is 200.
- `ACreditThatFails_LeavesTheDeclarationPendingToConfirmAgain`: an FK violation is injected into the
  credit. The declaration stays Pending and a later confirm succeeds.

The existing `ConfirmingTwice…` and `RejectingAnAlreadyConfirmed…` tests still pass.

**N-2: blank or absent «مفعّل» keeps the account as it is.** `buffet_app`:

- `UsersController.cs`: new `GetFirstBoolUnlessBlank`.
- `TemplatesController.cs`: falls back to `known?.IsActive ?? true`.

Regression tests are in a new `UserImportTests.cs`, over real HTTP with an admin cookie sign-in and
antiforgery:

- `UsersImport_ABlankActiveCellKeepsEachAccountAsItWas`
- `TemplateUpload_WithoutTheActiveColumnKeepsASuspendedAccountSuspended`

**Both were run against the unfixed lines and failed**: the user was locked out, and the suspended
account was re-enabled. They pass with the fix.

**N-3: honest sugar chip.** `buffet_flutter` `drink_details_step.dart`: a chip is selected only when
it is `composer.sugarItemId`. The new `test/features/sugar_choice_test.dart` covers the following:

- The first spoon picks the first sugar.
- Tapping another sugar changes what `toRequest()` sends.
- Going back to zero clears it.
- Spoons with no sugar show no chip as chosen.

The second case was not run against the old line. It fails there by construction, because the old
expression selects the first chip.

**Docs:** the CLAUDE.md paragraph that said "the UI never picks a sugar item" was rewritten. It had
become untrue.

## 4. Business workflow verification

| Workflow | Evidence | Result |
|---|---|---|
| Authentication, 401, expired token | Existing Flutter tests (`unauthorized_interceptor_test`, `session_restore_test`); existing .NET API tests | VERIFIED (Unit and HTTP-integration). Not live. |
| Catalogue, categories, ownership | Code; `DrinkMenuTests`, `MenuOrderTests` | VERIFIED (HTTP-integration) |
| Favourites: save, list, replay, retired items | `FavouritesApiTests`; Flutter favourites and composer tests | VERIFIED. N-5 is open. |
| Order creation: lines, variants, sugars, extras | `OrderServiceTests`; composer tests; `sugar_choice_test` | VERIFIED. No E2E run. |
| Order lifecycle and duplicate protection | `OrderLifecycleTests`, idempotency tests; concurrency token reviewed | VERIFIED (DB-integration) |
| Staff serving and stock at Ready | `OrderServingServiceTests`, `StockLedgerConsistencyTests`, `queue_serve_test` | VERIFIED |
| Notifications | `account_notifications_test`; code review | VERIFIED WITH LIMITATIONS. Push is off on the host, and there was no device. |
| Personal stock declare and confirm | `PersonalStockServiceTests` (with the N-1 tests) | VERIFIED (DB-integration) |
| Stocktake | `StocktakePostingTests`, `StocktakeScreenTests` | VERIFIED (HTTP-integration) |
| Admin changes seen on mobile | Guest privilege freshness tests | VERIFIED for the guest flag only |
| Reports and variance | `VarianceReportTests`, `ReportingServiceTests` | VERIFIED |
| Excel import | `TemplateTests`, `UserImportTests` | VERIFIED for users. Items and locations rely on existing tests. |

**No workflow was exercised end to end against a deployed server in this pass.** The previous live
checks are recorded in `docs/backend-findings.md` (2026-09-27), and they predate both sets of
changes.

## 5. UI/UX findings

- **N-3, fixed:** the sugar chip claimed a selection that was not real.
- **N-5 and N-6, open:** described above.
- The selected sugar chip uses `brandLight` fill (1.18:1) with ink text and a checkmark. The
  checkmark carries the state, so this passes, but the fill alone does not.
- **No visual pass was done.** No emulator was run and no screenshots were reviewed in this
  session. The screenshot tests in `test/screenshots/` passed, but nobody looked at their images.
  The responsive suite (320dp, 1x/1.5x/2x, both locales) passed.

## 6. Security and privacy findings

**Authorization (code, plus existing HTTP tests):**

- `/orders/{id}` returns 404 for another user's order.
- Favourites are scoped to the caller.
- Declarations are checked with `IsVisibleTo`.
- Order lines resolve only against `GetItemsForAsync(requester)`, so another user's private item is
  dropped.
- `SourceOwner` is computed on the server and never taken from the client.
- No new IDOR was found in the diff.

**Logging:** the new audit entries carry ids and names only. No tokens or passwords appear in the
diff.

**`PrivacyInfo.xcprivacy` is not in the bundle**, and its contents need correcting before it is
added:

- It declares `DeviceID`. iOS never registers a push token, so that is over-declared.
- It omits `EmailAddress` (the sign-in username is sent to the server), `Name`, and
  `OtherUserContent` (order notes, guest names).
- Required-reason APIs: the plugins (`shared_preferences`, `flutter_secure_storage`, `local_auth`,
  `package_info_plus`, Firebase) ship their own manifests at current versions. Check the aggregated
  report in Xcode after archiving.

**Android:** `allowBackup=false` is right. `POST_NOTIFICATIONS`, `USE_BIOMETRIC` and `INTERNET` are
the only permissions, and each is used.

## 7. Apple release assessment

| Item | Status |
|---|---|
| Bundle id `com.defi.buffetApp`, deployment target 15.0 | PASS (source) |
| `NSFaceIDUsageDescription` (Arabic base) | PASS. The localised variants are not bundled yet. |
| `ITSAppUsesNonExemptEncryption` | PASS |
| `PrivacyInfo.xcprivacy` in the target | **FAIL**: not in `project.pbxproj`, and the contents need fixing (§6) |
| `.lproj` InfoPlist.strings in the target | FAIL: not in `project.pbxproj` (documented in `ios/Runner/README-localisation.md`) |
| Push / APNs | NOT VERIFIED: deliberately absent. With swizzling off, APNs token forwarding and the notification delegate must be added by hand when it is built. |
| Build or archive | NOT VERIFIED: no macOS or Xcode |
| Signing, entitlements, App Store Connect, reviewer account, privacy policy | EXTERNAL ACTION REQUIRED |
| Account deletion (guideline 5.1.1(v)) | EXTERNAL ACTION REQUIRED: accounts are created by an admin, not in the app. Confirm with Apple whether Custom App distribution is exempt. |

**Recommended distribution:** an Apple Business Manager **Custom App** for the company's own
organisation. Unlisted needs full public review, and this app is for one employer's staff only.

## 8. Google Play release assessment

| Item | Status |
|---|---|
| `applicationId com.defi.buffet_app`, minSdk max(flutter, 23), target = Flutter default | PASS (source) |
| Release signing from `key.properties` (keystore kept outside the repo) | PASS (source). Not exercised. |
| Permissions and backup | PASS |
| Firebase `google-services.json` present | PASS. The host service account is still unset, so push is off. |
| Debug or release build | See §9 |
| Data Safety form, privacy policy, reviewer account, account deletion URL | EXTERNAL ACTION REQUIRED |

**Recommended distribution:** **Managed Google Play private app** for the company's organisation.
That needs a managed Google account or EMM. Otherwise, a closed testing track.

## 9. Final test results

| Project | Test | Previous agent | Independent run (before my fixes) | Independent run (after fixes) |
|---|---|---|---|---|
| Flutter | `flutter analyze` | No issues | No issues (exit 0) | No issues (exit 0) |
| Flutter | `flutter test` | 867 passed | 867 passed (exit 0) | **869 passed** (exit 0; +2 `sugar_choice_test`) |
| .NET | `dotnet build BuffetApp.slnx` | 0 warnings, 0 errors | 0 / 0 | 0 warnings, 0 errors |
| .NET | `dotnet test tests/BuffetApp.Tests` | 456 passed | 456 passed, 0 skipped (LocalDB present) | **460 passed**, 0 skipped (+2 `PersonalStockServiceTests`, +2 `UserImportTests`) |
| Flutter | Android debug APK | not built | — | **Debug APK built.** Signed release AAB: Gradle produced `app-release.aab` (61 MB), but Flutter reported "failed to strip debug symbols from native libraries" (cmdline-tools/NDK incomplete), so the bundle is unstripped. Install cmdline-tools + NDK and rebuild before upload. Warnings: Kotlin Gradle plugin deprecation in plugins; `CupertinoIcons` referenced by a dependency (none in `lib/`). |
| iOS | build or archive | not built | — | NOT VERIFIED (no macOS) |

## 10. Remaining blockers

1. **Redeploy the backend.** Without it, none of the server fixes (localisation, the N-1
   transaction, category checks, snapshots) are live. It needs whoever has the host. Deploy the
   branch, then re-run the live checks in `docs/backend-findings.md`.
2. **Push on a physical Android device with the app force-stopped.** It needs `Push__ServiceAccountJson`
   set on the host, then a phone. Follow `docs/firebase-setup-checklist.md`.
3. **The iOS target is incomplete.** It needs a Mac: add the privacy manifest (corrected, §6) and the
   `.lproj` files to the Runner target, archive, and read the privacy report.
4. **Store and legal paperwork.** Someone from the company needs to supply:
   - a privacy policy URL;
   - the Data Safety and App Privacy answers;
   - a reviewer account;
   - an account-deletion statement;
   - the Custom App / Managed Play enrolment.
5. **Product decisions on N-4 to N-6.** These need the owner. Each is a one-screen change once
   decided.

## 11. Final recommendation

1. **Is the Flutter app functionally reliable?** Yes, within what tests and code review can show. The
   one defect found (N-3) is fixed, and no device or visual pass was done.
2. **Are the backend and its business rules correct?** Yes, now. N-1 was a real stock-loss path,
   introduced by the previous fix, and it is closed with integration tests.
3. **Does the admin panel support the intended workflows?** Yes, with N-2 fixed. N-4 should be
   decided before the next bulk import.
4. **Are there remaining security concerns?** No code-level ones were found. The privacy manifest is
   both missing from the bundle and inaccurate.
5. **Is it ready for real internal users?** Yes for Android, once the backend is redeployed and push
   is enabled on the host. Do a short live smoke test first: order, serve, a declaration, and an
   import.
6. **Is it technically ready for Apple submission?** No. It needs Xcode work (blocker 3) and the
   external items.
7. **Is it technically ready for Google Play submission?** Not yet. The source is ready. A signed AAB
   and the console and legal items are outstanding.
8. **The five most important actions:**
   1. Redeploy `buffet_app`.
   2. Set the host push secret and test a force-stopped device.
   3. Decide N-4 (role on import) before the next import.
   4. Fix and bundle the iOS privacy manifest on a Mac.
   5. Prepare the privacy policy, Data Safety, reviewer account and private-distribution
      enrolment.
