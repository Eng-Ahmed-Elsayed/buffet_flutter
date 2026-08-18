# Digital Buffet — Flutter client

The mobile app for the Digital Buffet ordering system: **employee view and staff view**. Admin work
(import, reporting, audit) stays on the web.

The backend lives in a separate repository at `../buffet_app` (ASP.NET Core 10). This folder holds
the client, plus the reference material copied out of that repo.

## Start here

| | |
|---|---|
| [docs/flutter-app-guide.md](docs/flutter-app-guide.md) | **The build reference.** Brand tokens, architecture, auth and biometric flows, screen-by-screen rules, definition of done |
| [docs/staff-api-spec.md](docs/staff-api-spec.md) | The staff endpoints, and four places the implementation differs from the original spec |
| [docs/contracts/](docs/contracts/) | The C# wire contracts, copied verbatim — mirror these when writing the Dart models |
| [assets/images/](assets/images/) | The logo: full lockup and mark |

Read §0 of the guide first. Three implementation deviations change what the staff screens can
render, and one of them (declarations are admin-only) means a screen that looks obvious should not
be built at all.

## Before writing widgets

Design and approve the screens first — §1 of the guide lists the five that carry the domain rules,
and what deliberately should *not* be designed.

## The rules most likely to be broken

These come from the domain and are not obvious from the API shape alone:

1. **Stock is deducted at `Ready`, not `Completed`.** Ready = the drink was made; Completed =
   handed over.
2. **Shortages warn but never block.** Never disable a control on a stock reading.
3. **Violet means "from my own jar"**, throughout. Do not reuse it for generic selection.
4. **A declaration creates nothing** until an admin confirms receipt — say "awaiting confirmation",
   never "added".
5. **Arabic RTL first.** Only `start`/`end`, never `left`/`right`.
6. **Compare order status by name, never by the enum ordinal** (`Ready = 4`, out of workflow order).

## Assets

| File | Use |
|---|---|
| `assets/images/logo-defi.png` | Full lockup — login, about |
| `assets/images/logo-defi-mark.png` | Mark alone — app bar, splash, notification icon |

The palette is sampled from the mark's navy-to-violet gradient, so never recolour the logo to match
a theme; the theme already matches the logo. Declare both in `pubspec.yaml` under `assets:`.
