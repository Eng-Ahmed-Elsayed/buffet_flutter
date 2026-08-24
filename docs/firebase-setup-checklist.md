# Firebase setup — what I need from you

**Status:** blocking. Nothing in the push work can be tested end to end until this is done, and it
is the only item in the plan with an external dependency. Everything else (the notification centre,
the doc amendments, the queue improvements) proceeds without it.

**Time:** about 30–45 minutes for Android only. Add ~30 minutes and an Apple Developer account
(US$99/year) if iOS is in scope.

**What you are creating:** a Firebase project whose only purpose is Cloud Messaging — the channel
that lets the server tell an employee their drink is ready when the app is closed. No other
Firebase product is used: no Analytics, no Crashlytics, no Firestore, no Auth. Decline them when
offered.

---

## Why this is needed at all

An employee places an order and puts their phone down. Android then puts the app to sleep, and in
Doze mode the operating system **does not run** `JobScheduler` — which `WorkManager` is built on —
so no amount of background polling will tell them their coffee is ready. A high-priority push is
the only mechanism Android sanctions for waking an app for a time-sensitive message, and FCM is the
only way to send one.

We send exactly two kinds: **order ready** and **order cancelled**. Nothing else earns a push.

---

## Decisions I need from you first

### 1. One project or two?

| Option | Verdict |
|---|---|
| **One project** (`digital-buffet`) | Simplest. A test push from a developer machine can reach a real employee's phone. |
| **Two projects** (`digital-buffet-dev`, `digital-buffet-prod`) | **Recommended.** Standard practice, and it makes the mistake above structurally impossible. |

Two projects means two of everything below. If you would rather start with one and split later,
that is workable — say so and I will keep the config a single switch.

### 2. Who owns the project?

It should live under a **company Google account**, not a personal one. Whoever creates it is the
Owner, and moving a Firebase project between accounts later is awkward. If there is a shared
company Google Workspace account, use that and add yourself as Owner.

### 3. Is iOS in scope now?

Push on iPhone requires a **paid Apple Developer Program membership** (US$99/year). If the buffet
runs on Android handsets only, skip every iOS step below and tell me — it removes real work.

---

## Part A — Create the project

1. Go to <https://console.firebase.google.com> and sign in with the account from decision 2.
2. **Create a project**. Name it `digital-buffet` (or `digital-buffet-prod`).
3. When it offers **Google Analytics**, choose **disable**. We do not use it, and enabling it
   attaches a data-collection agreement you would otherwise have to review.
4. Wait for provisioning, then open the project.

---

## Part B — Register the Android app

The application ID must match **exactly**, character for character. Ours is:

```
com.defi.buffet_app
```

1. On the project overview, click the **Android** icon.
2. **Android package name:** `com.defi.buffet_app`
3. **App nickname:** `Digital Buffet (Android)` — internal label only.
4. **Debug signing certificate SHA-1:** leave blank. It is only needed for Google Sign-In and
   Dynamic Links, neither of which we use.
5. Click **Register app**, then **download `google-services.json`**.
6. **Send me that file.** Do not commit it yourself — I will place it and add the gitignore entry.

> ⚠️ The Android application ID (`com.defi.buffet_app`, with an underscore) and the iOS bundle ID
> (`com.defi.buffetApp`, camelCase) **are genuinely different** in this project. That is
> pre-existing and not a mistake to correct now — but it does mean you cannot copy one into the
> other when registering. Use each exactly as written.

---

## Part C — Register the iOS app *(skip if iOS is out of scope)*

Our bundle ID is:

```
com.defi.buffetApp
```

1. On the project overview, click the **iOS** icon.
2. **Bundle ID:** `com.defi.buffetApp`
3. Register, then **download `GoogleService-Info.plist`** and send it to me.

### The APNs key — the part people miss

Firebase cannot deliver to iPhones on its own; it hands the message to Apple. It needs a key to do
that.

1. Go to <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles** → **Keys**.
2. Create a key, name it `Digital Buffet Push`, tick **Apple Push Notifications service (APNs)**.
3. Download the `.p8` file. **Apple lets you download it exactly once.** Store it somewhere durable
   — a password manager, not a Downloads folder.
4. Note the **Key ID** (10 characters, shown on the page) and your **Team ID** (top-right of the
   developer portal, also 10 characters).
5. Back in Firebase: **Project settings → Cloud Messaging → Apple app configuration → APNs
   Authentication Key → Upload**. Provide the `.p8`, the Key ID, and the Team ID.

Also confirm the App ID in the Apple developer portal has the **Push Notifications** capability
enabled.

---

## Part D — The server credential (the important one)

This is what lets our backend actually send. It is a **secret** — treat it like a password.

1. **Project settings** (gear icon) → **Service accounts** tab.
2. Click **Generate new private key** → confirm. A `.json` file downloads.
3. Send it to me **through a secure channel** — a password manager share, or an encrypted message.
   **Not** email, and **not** a commit.

### What this file can do, so you understand the sensitivity

It authorises sending push notifications to every device registered to this Firebase project. A
leaked key means someone can push arbitrary notifications to your employees' phones. It cannot read
your database or your orders — but it can impersonate the app in the notification shade, which is
quite bad enough.

It will be stored as an environment variable on the host (`Push__ServiceAccountJson`), never in
`appsettings.json` and never in the repository. I will wire that up, and the app is written to run
normally when it is absent — push simply stays off, and the in-app notification list still works.

### Also note the Project ID

**Project settings → General → Project ID** (something like `digital-buffet-a1b2c`). Send it along;
it is not secret, and the sender needs it.

---

## What to send me, in summary

| Item | Where from | Secret? |
|---|---|---|
| `google-services.json` | Part B step 5 | No, but gitignored anyway |
| `GoogleService-Info.plist` | Part C step 3 *(iOS only)* | No, but gitignored anyway |
| Service account `.json` | Part D step 2 | **Yes — secure channel only** |
| Project ID | Part D | No |
| Confirmation the APNs key is uploaded | Part C *(iOS only)* | — |

Plus your answers to the three decisions at the top.

---

## What I do once I have them

1. Place the config files and add gitignore entries with `.example` companions, so a fresh clone
   fails loudly rather than silently building against the wrong project.
2. Add `firebase_core`, `firebase_messaging` and `flutter_local_notifications` to `pubspec.yaml`
   (already approved), plus the Google Services Gradle plugin.
3. Generate `lib/firebase_options.dart` via `flutterfire configure`. That file **is** committed —
   it holds only public project identifiers.
4. Add the `DeviceTokens` table, the register/unregister endpoints, and the FCM sender on the
   backend, hooked into the existing `NotificationService` so no caller changes.
5. Wire the client: register the token on sign-in, unregister on sign-out (a shared counter device
   must not keep pushing the previous person's orders), two notification channels, and deep-linking
   from a notification tap through to the order — including the case where the tap arrives while
   the app is sitting at the biometric lock screen.

## What still needs you afterwards

Push cannot be verified in an emulator or by an automated test. Someone has to hold a real phone.
When the code is ready I will need:

- A physical **Android** device, with the app **force-stopped**, receiving an order-ready push.
  That closed-app case is the entire justification for this work.
- The same on a physical **iPhone**, if iOS is in scope.
- A sign-out check: sign out on one device, confirm it stops receiving while another still does.

---

## Two things worth deciding now, not later

**Notification text is Arabic-only.** Server-side notification messages are hard-coded Arabic today
(unlike API error messages, which are localised). So an employee using the app in English will get
an Arabic push. This is pre-existing and out of scope for the push work itself, but push makes it
visible in a new place. Worth raising as its own backend task.

**Android notification channel behaviour is frozen at creation.** Once a device creates a channel,
its importance and sound cannot be changed by an app update — only the user can change it. So the
two channels (`order_ready` at high importance, `order_cancelled` at default) need to be right the
first time. I have set them per the plan; if you want cancellations to also make a sound, say so
before this ships rather than after.
