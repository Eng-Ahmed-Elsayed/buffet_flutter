# Backend request: client-written Arabic is stored as `?`

**Repo:** `../buffet_app` (ASP.NET Core 10)
**Severity:** high — this is an Arabic-first application in which users currently cannot write
Arabic free text.
**Found:** 2026-08-19, against `http://digitalbuffet.runasp.net/api/v1` with `sara@company.com`.

---

## Symptom

Arabic sent by the client is persisted as question marks, one `?` per character.

| Field | Sent | Stored and returned |
|---|---|---|
| `notes` | `سكر خفيف` | `??? ????` |
| `locationText` | `خلف المخزن` | `??? ??????` |
| `lineNote` | `بدون حليب` | `???? ????` |

Reproduce:

```bash
TOKEN=$(curl -s -X POST http://digitalbuffet.runasp.net/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"sara@company.com","password":"admin123"}' | jq -r .token)

curl -s -X POST http://digitalbuffet.runasp.net/api/v1/orders \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json; charset=utf-8' \
  --data-binary '{"lines":[{"drinkItemId":8,"drinkNameAr":"Coffee","sugarSpoons":0,
    "variantId":1,"sugarItemId":null,"extraItemIds":[],"lineNote":null,
    "drinkFromOwn":false,"sugarFromOwn":false,"ownExtraItemIds":[]}],
    "notes":"سكر خفيف","locationId":1,"idempotencyKey":"enc-test-0001"}'

# then read it back — notes comes back "??? ????"
```

## It is the write path, not the response encoding

This is the important diagnostic. Arabic the **server already owns** returns perfectly in the very
same response body that mangles the client's:

```jsonc
{
  "locationText": "مكتبي",             // server-owned (managed location) — correct
  "drinkNameAr": "قهوة تركية بالهيل",   // server-owned (item name)       — correct
  "notes": "??????"                     // client-sent                    — mangled
}
```

So JSON serialisation, the HTTP response encoding, and the client are all fine. Something between
the deserialised C# string and the stored row is doing a lossy conversion.

**The clearest single piece of evidence.** Cancelling order 30 with the Arabic reason
`نفدت المادة` produced this notification message:

```
"تم إلغاء طلبك رقم 30. السبب: ???? ??????"
 └─ server's own Arabic: intact ─┘  └─ client's Arabic: mangled ─┘
```

Both halves are the same C# string, serialised by the same code, sent over the same response. Only
the half that made a round trip through storage as a client-supplied value is destroyed. That rules
out every explanation except the write path.

## Likely cause

The character count is preserved exactly — 8 Arabic characters become 8 `?` — which is the
signature of a Unicode→single-byte codepage conversion, not truncation or double-encoding.

Two usual suspects, in order of likelihood:

1. **The column is `varchar`, not `nvarchar`.** A `varchar` column under a non-Arabic collation
   stores `?` for every character outside its codepage. This would affect exactly the fields
   observed — the free-text ones added for orders — while leaving item and location names (likely
   `nvarchar`, or seeded through a different path) intact.
2. **The connection or command is not sending Unicode parameters.** If any of these fields are
   written through raw SQL with a non-`N`-prefixed literal, or a parameter typed as
   `SqlDbType.VarChar`, the same loss happens even against an `nvarchar` column.

Sending `Content-Type: application/json; charset=utf-8` explicitly makes no difference, which rules
out request-side negotiation.

## Fields to check

Everything a client can write as free text:

- `Order.Notes` — from `PlaceOrderApiRequest.Notes`
- `Order.LocationText` — from `PlaceOrderApiRequest.LocationText`
- `OrderLine.LineNote` — from `OrderLineDto.LineNote`
- `Order.OnBehalfOfName` — same shape; not tested but almost certainly affected
- `CancelOrderRequest.Reason` and `DeclareMaterialRequest.Note` — same shape, not yet tested

## Verification

After the fix, the reproduce script above should return `"notes": "سكر خفيف"` unchanged. Note that
**rows already written are lost** — the original characters are not recoverable from `?`, so
existing test data will stay mangled.

## Client status

**No client change will help, and none has been made.** The bytes leave the app correctly encoded;
this is entirely server-side. Once fixed, Arabic notes will work with no client release.
