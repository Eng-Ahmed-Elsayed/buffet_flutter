# Backend request: `drinkSourceOwnerName` is empty when the jar is overdrawn

**Repo:** `../buffet_app` (ASP.NET Core 10)
**Severity:** medium — staff are told a drink came from the buffet when it came
from an employee's own (depleted) jar, so nobody knows to reconcile it.
**Found:** 2026-08-19, against `http://digitalbuffet.runasp.net/api/v1`.

---

## Symptom

`StaffOrderLineDto.DrinkSourceOwnerName` is populated when the employee's
balance is **positive** and empty when it is **negative** — even though both
orders were placed with `drinkFromOwn: true`.

Isolated with two orders from `sara@company.com`, differing only in balance:

| Order | Item | Sara's balance | `drinkFromOwn` sent | `drinkSourceOwnerName` returned |
|---|---|---|---|---|
| 45 | 7 — قهوة تركية بالهيل | **-6.0** (`Out`) | `true` | `""` ❌ |
| 46 | 2 — نسكافيه جولد | **160.0** (`Ok`) | `true` | `"سارة العتيبي"` ✅ |

The same empty value appears in the `/ready` warning, which is the one place it
matters most:

```jsonc
{"orderId":45,"status":"Ready","warnings":[
  {"itemId":7,"nameAr":"قهوة تركية بالهيل",
   "ownerDisplayName":"",        // ← whose jar? the warning cannot say
   "shortfall":12.0000,"unit":"جرام"}]}
```

## Why it matters

This is exactly the case the source label exists for. **Shortages warn but
never block** — so an employee ordering from an empty jar is a supported,
expected flow, and the resulting negative balance is for an admin to
reconcile. But the queue card tells staff `Drink: Buffet`, and the shortage
warning cannot name whose jar ran out. The overdraw is invisible to the people
standing at the counter.

An order that draws on a *positive* balance is labelled correctly, so the
plumbing works — it appears to be a lookup that resolves the owner through the
current balance row and returns nothing when that row is at or below zero.

## Suspected cause

Something along the lines of resolving the source owner by querying for a
balance `> 0`, rather than reading the ownership recorded on the order line
itself. The order already knows it was placed `drinkFromOwn: true` against a
specific employee; the name should come from that, not from whether they still
have stock left.

## Expected

`DrinkSourceOwnerName` (and `StockWarningDto.OwnerDisplayName`) should name the
employee whenever the line was placed against their own stock, regardless of
the balance — including when it is zero or negative.

## Client status

**No client change is needed or has been made.** The client renders the field
faithfully: a populated name gives the violet "from X's jar" chip, and an empty
one correctly reads as buffet stock — verified on device with order 46, which
displays `Drink: سارة العتيبي's jar` in violet. Both the chip and the shortage
banner already guard against an empty name, so the fix will surface with no
client release.
