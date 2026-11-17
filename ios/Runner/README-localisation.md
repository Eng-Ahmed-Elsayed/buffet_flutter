# iOS home-screen name & Privacy Manifest — one manual Xcode step

`ar.lproj/InfoPlist.strings` and `en.lproj/InfoPlist.strings` set the
home-screen name and Face ID prompt per locale (البوفيه الرقمي / Digital Buffet),
matching what `values-ar/strings.xml` and `values/strings.xml` already do on Android.
`PrivacyInfo.xcprivacy` declares Apple's Required Reason APIs and privacy disclosures.

**They are not yet referenced by `Runner.xcodeproj`.** Files that Xcode does not
know about are not copied into the bundle, so until this is done the fallback
in `Info.plist` is what appears on the home screen and `PrivacyInfo.xcprivacy` is omitted.

Doing it needs Xcode on macOS, which is why it is written down rather than
committed as a hand-edited `project.pbxproj` — a corrupted pbxproj is far worse
than a pending step:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Drag both `.lproj` folders and `Runner/PrivacyInfo.xcprivacy` onto the **Runner** group. Tick *Copy items if
   needed* off (they are already in place) and *Add to targets: Runner* on.
3. Select `Info.plist` → File inspector → **Localize…** → choose Arabic, then
   tick English as well.
4. Confirm `Runner` → Build Phases → Copy Bundle Resources lists both
   `InfoPlist.strings` entries and `PrivacyInfo.xcprivacy`.
5. Build to a device and check the home-screen name follows the device
   language.

Verify with:

```bash
plutil -p "$(find ~/Library/Developer/Xcode/DerivedData -name 'Runner.app' | head -1)/ar.lproj/InfoPlist.strings"
```
