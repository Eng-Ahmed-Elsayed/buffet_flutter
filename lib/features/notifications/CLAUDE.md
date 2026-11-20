# Notifications and push

Loaded when working in this directory. Moved out of the root CLAUDE.md *Current state*;
the rules hold for the notification centre, push, and the local order alerts (`lib/data/local/`). The root file's Standing rules and Domain rules still apply here.

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

**Account says when notifications are off** (Android, `lib/data/local/notification_settings.dart`),
with a button that opens the app's system notification settings (a `MethodChannel` in
`MainActivity.kt`). It checks again when the app resumes. It is on Account only, never Home: the
app still works without notifications, so this is information, not a nag. Push reaching one phone
and not another (reported 2026-09-28) is a device-side cause, since the server message is a visible
high-priority `notification` payload: a declined permission, OEM battery or autostart limits, or
a different account signed in on that phone.
`settings_screen_test.dart`.

Still unverified: **push on a physical Android handset with the app force-stopped.** That is the
case the whole feature exists for and no emulator or test exercises it — see
[docs/firebase-setup-checklist.md](docs/firebase-setup-checklist.md). The plan is
`~/.claude/plans/staff-view-expressive-lecun.md`.
