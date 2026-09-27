# Backend request: a description and a menu group on each drink

**Repo:** `../buffet_app` (ASP.NET Core 10)
**Status: SHIPPED in the backend repo 2026-09-27** (commits `4c91a7e`, `19e80f0`, `9337d8d`; contracts synced into `docs/contracts/`). **Not yet deployed** to digitalbuffet.runasp.net as of that date. The client builds against it with every field optional.
**Severity:** medium. This is a feature, not a bug. The new app design needs both fields, and the
client falls back cleanly until they ship.
**Raised:** 2026-09-24, from the Figma redesign (see [figma-redesign.md](figma-redesign.md)).

---

## Why

The new design is built around browsing a menu rather than picking from a grid:

- **Home** has category chips across the top (the mock-up shows "Nescafé · Tea · Juices") and a
  menu list where each row gives a drink its name *and a one-line description*.
- **Drink Details** has a hero image, the name and a paragraph describing the drink, above the
  preparation, sugar and extras controls.

`CatalogueItemDto` can provide neither today:

| Need | Today | Why it falls short |
|---|---|---|
| Group chips | `Category` | Always `"Drink"` for a drink. It is the `ItemCategory` enum (`Drink`/`Sugar`/`Extra`), which separates drinks from sugars, not drinks from each other |
| Description | — | No field. `InventoryItem` has no text beyond the two names |

Both are admin-entered content, so the client cannot derive them. Guessing a group from the Arabic
name (does it contain «شاي»?) would be wrong often enough to mislead.

## Requested changes

Each change stands alone and can ship separately. **The description is the more valuable of the
two.** Without it, Drink Details is a photo and a title.

### 1. Description

- `InventoryItem`: add `DescriptionAr` (`string?`) and `DescriptionEn` (`string?`), capped at
  about 200 characters. A description is one or two lines, not an article.
- `CatalogueItemDto`: add `DescriptionAr` and `DescriptionEn` (`string?`, null when not set).
  Mapped in `EmployeeApi.cs`, in the `Map` function that builds `CatalogueItemDto` (~line 214).
- Admin: two text areas on `Views/Inventory/Edit.cshtml`, shown for drinks only.

### 2. Menu group

Please use a **managed list**, not a free-text field on the item. Free text splits one group into
two the first time somebody types «شاى» for «شاي», and the client would then show both chips.

- A new `DrinkGroup` table: `DrinkGroupId`, `NameAr`, `NameEn`, `SortOrder`, `IsActive`, plus admin
  create / rename / reorder / retire.
- `InventoryItem`: add a nullable `DrinkGroupId`. Only drinks carry one, and an ungrouped drink is
  valid.
- `CatalogueItemDto`: add `DrinkGroupId` (`int?`).
- `CatalogueResponse`: add `DrinkGroups`, a list of `DrinkGroupDto(DrinkGroupId, NameAr, NameEn,
  SortOrder)` covering **active groups that contain at least one active drink**, so the client
  never renders a chip that filters down to nothing.
- Admin: a group dropdown on `Views/Inventory/Edit.cshtml` for drinks, and a small page to manage
  the groups.

## What the client will do

Until these fields appear in `docs/contracts/ApiContracts.cs`, the client does not read them.
Standing rule: never invent a field.

- **No description:** the menu row shows the name alone, and Drink Details goes from the title
  straight to the controls. Nothing looks broken.
- **No groups, or `DrinkGroups` empty:** the chips fall back to source («من موادي» /
  «من البوفيه»), which the catalogue already supports. Once groups exist, drinks without a group
  appear under an «أخرى» / "Other" chip, so a drink the admin has not grouped yet never disappears.

## Explicitly not requested

The Figma file also shows star ratings, cup sizes (S/M/L), per-extra amounts ("mint leaves"),
"Popular" and "Recommended for you". None of them has a business owner, so none is requested:

- Sizes are covered by **preparations** (`VariantDto`).
- "Popular" is covered by the user's own **favourites**.
