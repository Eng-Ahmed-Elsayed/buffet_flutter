# First-launch explainer

Loaded when working in this directory. Moved out of the root CLAUDE.md *Current state*;
 The root file's Standing rules and Domain rules still apply here.

**The first-launch explainer (`/welcome`) shows once per install, before the first sign-in, and
never to someone who already uses the app.** Its flag lives in `PreferencesStore` and survives
sign-out. **Any session stage (signed in, locked, forced password change) marks it seen**, and so does a
signed-out device with a remembered email or a just-ended session (`hasUsedAppProvider`, seen on
the emulator); see `onboardingControllerProvider`. Without that, everyone who signed in before it existed would be sent
through three slides the moment their session ended, burying the "session expired" notice below.
`signedOutRedirect` holds on the splash while the flag loads. The entry screens (splash, explainer,
sign-in, lock) share `BrandBackdrop` and `BrandLockup`. The explainer's slides are licensed photographs
([docs/asset-credits.md](docs/asset-credits.md)), never generated ones, with the text on
`BrandColors.photoScrim`; a new photo is credited there. **No text sits over the glow's peak**: the
link blue drops to about 4:1 there, so the explainer's Skip is in ink.
