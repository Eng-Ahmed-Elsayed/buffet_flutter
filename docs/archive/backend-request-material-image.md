# Backend request: add `ImageUrl` to `MyMaterialDto`

**Repo:** `../buffet_app` (ASP.NET Core 10)
**Requested by:** Flutter client, for the "my materials" screen (§7.5)
**Status:** **Resolved** — shipped 2026-08-19 (`buffet_app` commit `466e758`). Verified live: the
materials screen shows real uploaded photographs, falling back to a category glyph when the field
is null or the file 404s. Kept as the record of why the field exists, and of the relative-vs-absolute
inconsistency noted below.

> This header read "pending" for five days after the feature shipped. If you resolve a request,
> say so here — the status line is the only thing a reader checks.

---

## Why

`GET /materials/mine` currently returns no image reference, so the materials screen has nothing to
render but a name and a level band. The composer already shows real uploaded images via
`CatalogueItemDto.ImageUrl`; the same jar of coffee should not appear as a generic glyph one screen
later. A client-side join from `/catalogue` on `ItemId` was considered and rejected — it breaks for
any material the user owns that is not currently an active catalogue item, and it costs an extra
round trip on a screen that otherwise needs one call.

## The change

One field, appended to the end of the record so the positional constructor stays
source-compatible for existing callers:

```csharp
/// <summary>One of the caller's own materials.</summary>
public sealed record MyMaterialDto(
    int ItemId,
    string NameAr,
    string Unit,
    decimal Quantity,
    int ServingsLeft,
    string Level,
    string? ImageUrl);   // <-- added
```

## Expected semantics

Match `CatalogueItemDto.ImageUrl` exactly — the client resolves both through the same code path:

- **Relative**, not absolute (e.g. `/uploads/items/42.png`), resolved by the client against the API
  host. Do not return a fully-qualified URL; the client would then have to strip the host to
  support environment switching.
- **Nullable.** `null` is expected and normal for an item whose admin never uploaded a picture. The
  client falls back to a category glyph — no error, no placeholder image request.
- **A `404` on the file is not an error condition.** §7.1 already notes the uploads folder is not
  covered by database backups, so a row can reference a file that no longer exists. The client
  treats a failed image fetch as "use the fallback" and does not surface it to the user.

## Where it comes from

The value should be the same `ImageUrl` already stored on the underlying item that
`CatalogueItemDto` reads — the materials projection needs to select it from the item entity rather
than compute anything new. If the projection currently selects only the balance columns, this adds
the item's image column to that select.

## Verification

`GET /api/v1/materials/mine` with a token for an account holding at least one material whose item
has an uploaded image should return that item's relative path, and `null` for one without:

```jsonc
[
  { "itemId": 12, "nameAr": "بن تركي",   "unit": "جرام", "quantity": 500, "servingsLeft": 25, "level": "High", "imageUrl": "/uploads/items/12.png" },
  { "itemId": 19, "nameAr": "حليب بودرة", "unit": "جرام", "quantity": 90,  "servingsLeft": 4,  "level": "Low",  "imageUrl": null }
]
```

Wire format is `camelCase` via System.Text.Json defaults, as with every other contract here.

## Client behaviour until this ships

The Flutter model already carries `imageUrl` as a nullable field. Until the API returns it, every
material deserialises with `imageUrl == null` and renders the fallback glyph — the screen works,
it simply shows no photographs. **No client change is needed when the field starts arriving**; the
images appear on their own.
