# Sign-in and session

Loaded when working in this directory. Moved out of the root CLAUDE.md *Current state*;
 The root file's Standing rules and Domain rules still apply here.

**Sign-in asks only for the name before `@defi.com.eg`** (`ApiConfig.emailDomain`, §5.1). The
domain shows beside the name, on its right in both languages, since the field is LTR; a full
address, typed or pasted, goes as it is, which is how the `company.com` test accounts still sign
in. (Digits: see the root file.)

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
