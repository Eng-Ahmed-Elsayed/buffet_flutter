# Backend request: publish a variant's ingredients on `VariantDto`

**Raised:** 2026-08-20. **Resolved:** 2026-08-20 — `ingredientItemIds` is on the wire, and the
client marks the chip and shows the hint. Kept as the record of why the field exists.

**Was:** the double-portion warning in the mobile composer. **Kind:** B — the backend enforced a
rule the client could not predict.

> **Shipped.** The measured figure came back as 22g recipe + 30g extra = **52g**, now pinned by a
> test in `OrderFulfillmentServiceTests` so the rule the warning describes cannot silently change.
> Publishing cost no extra query: `GetVariantsAsync` already did `.Include(v => v.Ingredients)`.

## What the web does and the app cannot

Picking **Milk** as an extra on a **French** coffee is a *double* portion: the preparation already
pours milk, and the order deducts it twice. This is correct — two pours, two deductions — but as
the web's own comment puts it, *"it is the kind of correct that looks like a bug on the stock
report if nobody said so first."*

So the web says so first, in three places:

| Where | String | Source |
|---|---|---|
| On the extra chip | `ExtraAlreadyInPreparation` — "This preparation already includes it — choosing it adds a second portion." | `_OrderFormFields.cshtml:331` |
| Under the extras row | `ExtraDoublesHint` — "You picked an extra that this preparation already includes, so a double portion will be used." | `_OrderFormFields.cshtml:350` |
| On the admin's allowed-extras screen | `…is already poured by {1}. Allowing it as an extra as well means an employee who picks both gets a double portion, and stock is deducted twice.` | `SharedResource.en.resx:1844` |

It can do this because the recipe is right there in the page:

```razor
data-variants="@(System.Text.Json.JsonSerializer.Serialize(variants.Select(v => new {
    id = v.VariantId, name = v.DisplayName, def = v.IsDefault,
    /* What this preparation already pours. */ ... })))"
```

**The API sends none of it.** `VariantDto` is four scalars:

```csharp
public sealed record VariantDto(int VariantId, string NameAr, string NameEn, bool IsDefault);
```

`ItemVariant.Ingredients` (a `List<VariantIngredient>`) exists in the domain model and is what the
Razor view reads, but it stops at the API boundary. The mobile client therefore cannot know that
French pours milk, and a user who taps Milk on a French coffee gets a silent double deduction with
no warning at all — the one thing all three web strings exist to prevent.

This is the **same shape of bug** as `allowedExtraItemIds` before it shipped: a rule enforced
server-side, invisible to the client, failing quietly rather than loudly. The difference is that a
disallowed extra is dropped, while this one is charged twice.

## Requested change

Add to `VariantDto`, appended last so the positional record stays source-compatible:

```csharp
/// <param name="IngredientItemIds">
/// Items this preparation already pours — the milk in a فرنساوي. Empty when the variant has no
/// recipe beyond the drink itself.
/// <para>
/// Published so the client can warn that choosing one of these as an <em>extra</em> means a second
/// portion and a second deduction. Ingredients are part of the recipe and cannot be declined, which
/// is what distinguishes them from <see cref="ItemAllowedExtra"/> — do not use this to filter the
/// extras picker, only to annotate it.
/// </para>
/// </param>
IReadOnlyList<int> IngredientItemIds
```

Populated from `ItemVariant.Ingredients` in the `/catalogue` handler, alongside the existing
`variantsByDrink` lookup — the ingredients are already loaded for the same variants.

An empty list, not null: unlike `AllowedExtraItemIds` there is no "unrestricted" case to
distinguish. A variant with no ingredients pours nothing extra, which is exactly what `[]` says.

## What the client will do with it

Mirror the web, in the same order of severity:

1. Mark the affected chip in the extras row while that preparation is selected — the mark moves
   when the user switches from French to Dark, since milk is in one and not the other.
2. Show the `ExtraDoublesHint` equivalent under the row once such an extra is actually ticked.

**A warning, never a block.** Same rule as a shortage: the doubling is a legitimate thing to order,
the user may well mean it, and disabling the chip would stop someone ordering a drink the system is
perfectly willing to make. Say what will happen and let them decide.

## What shipped

Both marks, mirroring the web. The chip carries a warning glyph and a tooltip while the poured
preparation is selected, and a hint appears under the row once such an extra is actually ticked.

Three properties are pinned by tests, because each is a way this could quietly go wrong:

- **The mark moves with the preparation**, not the drink — switching فرنساوي → غامق clears both the
  mark and the hint, since milk is in one recipe and not the other.
- **The extra stays orderable.** The chip is still selected and still selectable, the id is still
  sent, and the order button never goes off for it.
- **A preparation with no recipe flags nothing**, and a drink made one way has no variant at all.

Recorded in [dod-status.md](dod-status.md) under §8.
