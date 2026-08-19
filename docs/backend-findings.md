# Backend findings from building the client

Observations against the live API at `http://digitalbuffet.runasp.net/api/v1`, recorded
2026-08-18. These are **not** client bugs — each is something the backend either does differently
from the specification or does not yet do, with what the client does about it in the meantime.

---

## 1. `Accept-Language` does not localise the login error (confirmed)

**What the specification says.** §4: "Send `Accept-Language: ar` (or `en`) — *error messages are
localised server-side from that header*, so the app should display `ApiError.message` as-is rather
than mapping codes to its own strings."

**What actually happens.** `POST /auth/login` returns the same Arabic message either way:

```bash
$ curl -X POST .../auth/login -H 'Accept-Language: en' \
    -H 'Content-Type: application/json' -d '{"username":"probe@example.com","password":"wrong"}'
{"message":"البريد الإلكتروني أو كلمة المرور غير صحيحة."}   # 401

$ curl -X POST .../auth/login -H 'Accept-Language: ar' ... # identical
```

A malformed body (`{}`) returns the same Arabic string too.

**Scope not yet established.** Only the unauthenticated surface could be probed from here — every
other endpoint needs a token. It is unknown whether this is specific to the login handler or
applies to all server-side messages. **Worth checking with a real token before assuming either
way.**

**What the client does.** Nothing different — it sends `Accept-Language` from the chosen locale on
every request and surfaces `ApiError.message` verbatim, exactly as §4 requires. The consequence is
simply that an English-language user currently sees Arabic text for at least this one error. The
client is already correct for the moment the server starts honouring the header; no client change
will be needed.

**Why the client does not paper over it.** Mapping status codes to client-side English strings
would discard the server's actual message, which is often more specific than anything the client
could invent ("this account is disabled" vs a generic "sign-in failed"). §4 is explicit that the
message is authoritative. The fix belongs in the backend's localisation of its handlers.

---

## 2. `MyMaterialDto` has no `ImageUrl` (change requested)

`GET /materials/mine` returns no image reference, so the materials screen has nothing to draw but
a name and a level band — while the composer, one screen away, shows real uploaded photographs via
`CatalogueItemDto.ImageUrl`.

Specified in full in [backend-request-material-image.md](backend-request-material-image.md). The
Dart model already carries a nullable `imageUrl`, so **images appear on their own when the field
ships** — no client change required.

---

## 3. The API is served over plain HTTP

`http://digitalbuffet.runasp.net` has no HTTPS. Two consequences worth weighing:

- **The bearer token is readable in transit** by anything on the network path, and these tokens
  last **30 days with no refresh endpoint** (§4.2) — so a token captured once stays useful for a
  month, and cannot be rotated server-side without invalidating the signing key.
- Both platforms block cleartext by default. §11 anticipated this and the exceptions are in place,
  each **scoped to this one host** rather than a blanket allow:
  - `android/app/src/main/res/xml/network_security_config.xml`
  - the `NSAppTransportSecurity` block in `ios/Runner/Info.plist`

§11 is explicit: "**Production must be HTTPS**; do not ship the exception." Both files carry a
comment saying to delete them when the API moves. This is the one item on this page that is a
genuine security matter rather than a papercut.

---

## 4. No OpenAPI document exposed

`/swagger/v1/swagger.json` returns `404`, and §4 notes `/openapi/v1.json` is development-only. The
contracts in [contracts/](contracts/) remain the reference, which is what §4 prescribes anyway.

---

## Not yet verified

Everything requiring a token. In particular these are **assumed from the contracts, not observed**:

- The `warnings` array on a `200` from `/staff/orders/{id}/ready` (the shortage rule)
- `202 Accepted` from `/materials/declare`
- `GET /staff/queue` returning `Pending` + `InProgress` only
- `mustChangePassword` on a seeded account
- `201 duplicate:false` / `200 duplicate:true` on `POST /orders`

A staff test account and an employee test account would let all of these be checked against the
running server rather than the documentation.
