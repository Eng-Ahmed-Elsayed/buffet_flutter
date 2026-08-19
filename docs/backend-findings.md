# Backend findings from building the client

Observations against the live API at `http://digitalbuffet.runasp.net/api/v1`. Updated 2026-08-19
after test accounts were supplied, so most of this page is now **observed** rather than assumed.

Test accounts used: `sara@company.com` (Employee), `staff@company.com` (Staff),
`admin@company.com` (Admin).

---

## Confirmed working — the domain rules, verified end to end

Every rule in CLAUDE.md that could be exercised has been, against the running server:

| Rule | Evidence |
|---|---|
| **Stock deducts at `Ready`, not `Completed`** | Sara's jar went `138g / 11 servings` → `126g / 10` on `POST /staff/orders/26/ready`. Nothing moved at `/complete`. |
| **Shortages warn but never block** | Serving past an empty jar returned **`200`** with `status: "Ready"` and `warnings: [{itemId: 7, ownerDisplayName: "سارة العتيبي", shortfall: 6.0000, unit: "جرام"}]`. Never a `400`. The balance went to **`-6.0000`**. |
| **A declaration creates nothing** | `POST /materials/declare` returned **`202`** with `{"declarationId": 7}`; declaring 250g left the balance at `-6.0000`, unchanged. |
| **Status compared by name** | `/orders/mine` returns `"Ready"`, `"Pending"`, `"Completed"`, `"Cancelled"` — strings, never ordinals. |
| **`GET /staff/queue` is `Pending` + `InProgress` only** | After order 26 went `Ready` it vanished from the default queue; `?status=Ready` returned it. |
| **Declaration endpoints are admin-only** | A Staff token gets **`403`** on `/staff/declarations`. |
| **`SugarNameAr` is always null** | Confirmed on every queue line. |
| **Every line names its source owner** | One line carried `drinkSourceOwnerName: "سارة العتيبي"` and `sugarSourceOwnerName: ""` — a mixed-source line, which is exactly what the queue card exists to show. |
| **Idempotency** | Same key twice → `201 {"orderId":26,"duplicate":false}` then `200 {"orderId":26,"duplicate":true}`. Same order id. |
| **`404`, not `403`, on someone else's order** | Sara reading admin's order 40 got `404`. |
| **Cancelling a `Ready` order** | `204`, and the balance stayed `-6.0000` — reversed and re-booked as waste, so net unchanged. |

---

## 1. Client-written Arabic text is stored as `?` (CONFIRMED — needs a backend fix)

**The most significant finding on this page.** Arabic sent by the client is persisted as question
marks. This is an Arabic-first app in which users cannot write Arabic notes.

```bash
# Sent: "سكر خفيف"  → stored and returned as "??? ????"
# Sent: "خلف المخزن" → stored and returned as "??? ??????"
# Sent: "بدون حليب"  → stored and returned as "???? ????"
```

Affects every client-written text field observed: `notes`, `locationText`, and `lineNote`.

**It is a write-path problem, not a response-encoding one.** Arabic the *server* already owns comes
back perfectly in the same responses:

```jsonc
{
  "locationText": "مكتبي",                  // server-owned, correct
  "drinkNameAr": "قهوة تركية بالهيل",        // server-owned, correct
  "notes": "??????"                          // client-sent, mangled
}
```

The character count is preserved exactly (8 Arabic chars → 8 `?`), which is the signature of a
lossy encoding conversion on write — a non-Unicode column (`varchar` rather than `nvarchar`), or a
connection string without the right charset. Sending `Content-Type: application/json; charset=utf-8`
explicitly makes no difference.

**Suggested fix:** check the column types on the order/line tables for `notes`, `locationText` and
`lineNote`, and the collation/charset of the connection. **No client change will help** — the bytes
leave the app correct.

---

## 2. `POST` with no body needs `Content-Length: 0` (CONFIRMED)

`POST /staff/orders/{id}/ready`, `/start` and `/complete` take no request body. Sent with no body
and no `Content-Length` header, IIS rejects them before the application sees them:

```
HTTP 411 — "The request must be chunked or have a content length."
```

Adding `Content-Length: 0` makes the same call succeed. **Dio sets this automatically**, so the
Flutter client is unaffected — this is recorded because anyone testing these endpoints with `curl`
will hit it immediately and mistake it for a broken endpoint.

---

## 3. `MyMaterialDto.ImageUrl` — SHIPPED ✅

Live and working exactly as specified:

```jsonc
{"itemId": 7, "nameAr": "قهوة تركية بالهيل", "unit": "جرام", "quantity": 138.0000,
 "servingsLeft": 11, "level": "Ok", "imageUrl": "/uploads/items/item-7-914ab363.png"}
```

The file resolves (`200`, `image/png`). No client change was needed — the model already carried the
nullable field.

**One inconsistency worth knowing:** `/materials/mine` returns a **relative** path
(`/uploads/items/…`) while `/catalogue` returns an **absolute** URL
(`http://digitalbuffet.runasp.net/uploads/items/…`). Both work — `ApiConfig.imageUrl()` passes
absolute URLs through and resolves relative ones — but making them consistent would be tidier, and
the absolute form hard-codes the host into stored data, which breaks when the API moves to HTTPS or
a new domain. **Relative is the better of the two.**

---

## 4. `level` values are `Ok` / `Out`, not a four-band scale

Observed values on `/materials/mine`: **`"Ok"`** and **`"Out"`**. The client originally guessed at
`High`/`Medium`/`Low`/`Empty` from the design; `StockLevel` has been corrected to the observed
values, with `Low` retained as an unused third band and marked as never having been seen on the
wire. Unknown bands fall back to `Ok` — the quantity beside it is the real signal.

---

## 5. `Accept-Language` does not localise the login error (CONFIRMED)

`POST /auth/login` returns the same Arabic message under `Accept-Language: en`:

```json
{"message":"البريد الإلكتروني أو كلمة المرور غير صحيحة."}
```

**Scope:** still only observed on login. Authenticated endpoints have not been made to produce a
localised error for comparison. The client sends the header from the chosen locale on every request
and surfaces `ApiError.message` verbatim, per §4 — so it is already correct for whenever the server
starts honouring it.

---

## 6. The API is served over plain HTTP

Unchanged and still the one genuine security item on this page. The bearer token is readable in
transit and lasts **30 days with no refresh endpoint**, so a captured token stays useful for a
month.

Cleartext exceptions are in place, each scoped to this single host, and both carry a comment saying
to delete them when the API moves:

- `android/app/src/main/res/xml/network_security_config.xml`
- the `NSAppTransportSecurity` block in `ios/Runner/Info.plist`

§11: "**Production must be HTTPS**; do not ship the exception."

---

## 7. Undocumented response body on `/materials/declare`

The endpoint returns `{"declarationId": 7}`. `DeclareMaterialRequest` in the contracts documents
the request but no response type. The client ignores the body — it only needs the `202` — so this
is a documentation gap rather than a defect.

---

## Test data left behind

Exercising these rules created orders 26–40 on `sara@company.com` and `admin@company.com`, drove
sara's balance for item 7 (`قهوة تركية بالهيل`) to **`-6.0000` جرام**, and left **declaration 7**
pending confirmation. Worth resetting if this instance is used for anything else.
