# Apple App Store & Google Play Store Release Readiness Report

**Application:** Digital Buffet (`com.defi.buffet_app`)  
**Flutter Client Version (`pubspec.yaml`):** `1.0.0+3`  
**Audience / Distribution:** Internal business use distributed via Apple and Google platforms (free, no in-app purchases, no subscriptions, accounts provisioned by organization admin).

---

## 1. Readiness Matrix

| Area | Platform | Status | Evidence / Details |
|---|---|---|---|
| **Static Analysis & Automated Tests** | Both | **PASS** | `flutter analyze` -> `No issues found!`; `flutter test` -> **867 passed, 0 failed** (tested across AR/EN, reduced motion, 320dp responsive, semantics, biometric & auth state) |
| **Apple Privacy Manifest (`PrivacyInfo.xcprivacy`)** | iOS | **FIXED** *(pending Xcode project registration)* | Created [ios/Runner/PrivacyInfo.xcprivacy](file:///C:/Users/L/Documents/src/buffet_flutter/ios/Runner/PrivacyInfo.xcprivacy) declaring `NSPrivacyTracking = false`, linked app-functionality data types (`UserID`, `DeviceID`), and `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` |
| **Export Compliance (`ITSAppUsesNonExemptEncryption`)** | iOS | **FIXED** | Set `ITSAppUsesNonExemptEncryption = false` in `ios/Runner/Info.plist` (standard HTTPS/TLS and OS Keychain only) |
| **Firebase Method Swizzling Toggle (`FirebaseAppDelegateProxyEnabled`)** | iOS | **FIXED** | Set `FirebaseAppDelegateProxyEnabled = false` in `ios/Runner/Info.plist` while iOS push notifications remain intentionally deferred pending Apple Developer Program enrollment |
| **Localized iOS Face ID Prompt (`NSFaceIDUsageDescription`)** | iOS | **FIXED** *(pending Xcode project registration)* | Added localized `"NSFaceIDUsageDescription"` strings to `ios/Runner/ar.lproj/InfoPlist.strings` and `ios/Runner/en.lproj/InfoPlist.strings`, matching `Info.plist` fallback |
| **Xcode Bundle Resource Registration** | iOS | **NEEDS CONFIGURATION** | `ios/Runner/README-localisation.md` documents the required macOS Xcode step: drag `ar.lproj`, `en.lproj`, and `PrivacyInfo.xcprivacy` into `Runner.xcodeproj` (`Copy Bundle Resources`) so Xcode packages them into `.ipa` |
| **iOS Push (`GoogleService-Info.plist` & APNs Key)** | iOS | **EXTERNAL ACTION REQUIRED** *(intentionally deferred)* | `ios/Runner/GoogleService-Info.plist` is absent (checked: `False`), and Apple Developer Program enrollment + APNs key upload to Firebase Console are required once iOS push is activated |
| **Android Backup Hardening (`android:allowBackup="false"`)** | Android | **FIXED** | Added `android:allowBackup="false"` on `<application>` in `android/app/src/main/AndroidManifest.xml` to prevent cloud/ADB backup of sensitive local state alongside `EncryptedSharedPreferences` |
| **Android FCM Notification Channel Meta-Data** | Android | **FIXED** | Added `com.google.firebase.messaging.default_notification_channel_id` = `"order_ready"` in `android/app/src/main/AndroidManifest.xml` matching the client notification channel |
| **Android Release Signing & R8 ProGuard** | Android | **PASS** *(keystore local)* | `android/app/build.gradle.kts` enables `isMinifyEnabled = true`, `isShrinkResources = true`, `proguard-rules.pro` keeps `BiometricEnrolmentGuard`, `MainActivity`, `androidx.biometric.**`, `androidx.security.crypto.**`, `com.google.crypto.tink.**`; `android/key.properties` exists locally (gitignored) |
| **Android SDK & `google-services.json`** | Android | **PASS** *(SDK config note)* | `android/app/google-services.json` is present locally (`True`); `minSdk = maxOf(flutter.minSdkVersion, 23)`. Note: `flutter doctor -v` on this Windows machine reports `cmdline-tools` component missing and Android licenses not yet accepted |
| **Adaptive Launcher Icons** | Both | **PASS** | Generated icon assets verified in `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` and `ios/Runner/Assets.xcassets/AppIcon.appiconset/` (20px–1024px) |
| **Backend Production Push Configuration** | Backend | **EXTERNAL ACTION REQUIRED** | As recorded in `CLAUDE.md` and `docs/backend-findings.md`, backend host requires `Push__ServiceAccountJson` configured and redeploy of the `buffet_app` fixes (`Accept-Language: en`, order snapshot/concurrency fixes) |
| **Native Release Builds (`.aab`/`.apk` & `.ipa`)** | Both | **NOT VERIFIED** | Not built/archived in this session: macOS + Xcode are unavailable on Windows for iOS archive, and `flutter doctor -v` shows Android `cmdline-tools` missing + licenses unaccepted on this Windows host |
| **Store Console Declarations (Data Safety, Account Deletion, Distribution Mode)** | Store Consoles | **EXTERNAL ACTION REQUIRED** | Requires organization App Store Connect & Google Play Console configuration (Unlisted/Private vs internal/public review instructions, demo reviewer credentials, and Data Safety / Privacy labels matching `PrivacyInfo.xcprivacy`) |

---

## 2. Store Compliance & Policy Notes

1. **Account Deletion Policy (App Store Review Guideline 5.1.1(v) / Google Play Account Deletion):**
   - Digital Buffet does **not** provide self-service account creation inside the mobile app — employee and staff accounts are provisioned/imported and disabled by an organization Admin (`UsersController` / `TemplatesController`).
   - Because there is no in-app account sign-up, document clearly in App Review notes (Apple) and Google Play Console Data Safety forms that accounts are company-issued HR/IT directory accounts, and include the IT/Admin contact procedure to request deactivation/removal if Google Play asks for an administrative deletion contact URL.
2. **Demo Account & Review Access (Both Stores):**
   - Both Apple App Review and Google Play review teams require active demo credentials (employee and staff accounts) pointing to a reachable HTTPS server (`https://digitalbuffet.runasp.net`) unless distributed exclusively as Apple Unlisted / Private Managed Google Play / Enterprise internal distribution.
3. **Biometrics (`local_auth` + `NSFaceIDUsageDescription` + `USE_BIOMETRIC`):**
   - Localized Face ID usage strings explain rapid unlock for Digital Buffet; biometric enrollment change detection is protected by `proguard-rules.pro` keep rules on Android.

---

## 3. Exact Verification Commands Before Store Submission

On an Android-configured build host (after installing Android `cmdline-tools` and accepting `flutter doctor --android-licenses` with release `android/key.properties`):
```bash
flutter analyze
flutter test
flutter build appbundle --release
```

On a macOS build host with Xcode after completing `ios/Runner/README-localisation.md`:
```bash
flutter analyze
flutter test
flutter build ipa --release
```
