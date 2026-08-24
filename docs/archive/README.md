# Archive

Documents whose work has shipped. Kept, not deleted: each records *why* something exists, which is
the part that stays useful after the request itself is closed.

Nothing here describes pending work. If you are looking for what still needs doing, it is in
[../](../) — the active folder.

## What is here

| Document | Shipped | Why it was kept |
|---|---|---|
| [staff-api-spec.md](staff-api-spec.md) | 2026-08-18 | The four deviations at the end are still load-bearing, and are summarised in the guide's §0 and §8. |
| [backend-request-material-image.md](backend-request-material-image.md) | 2026-08-19 | Records the relative-vs-absolute `imageUrl` inconsistency between `/materials/mine` and `/catalogue`. |
| [backend-request-variant-ingredients.md](backend-request-variant-ingredients.md) | 2026-08-20 | Why `VariantDto.ingredientIds` exists and what the chip mark means. |
| [backend-request-declare-new-item.md](backend-request-declare-new-item.md) | 2026-08-20 | Why `declare-new` takes **packages** where `declare` takes base units — the trap that motivated it. |

## Which repo owns what

`flutter-app-guide.md`, `backend-flutter-parity.md` and `staff-api-spec.md` exist **byte-identical
in both repos** (`buffet_flutter/docs/` and `buffet_app/docs/`), with no stated source of truth.
That has already caused one drift: `docs/contracts/` went four commits stale before anyone noticed.

Until someone decides otherwise, the convention is:

- **`buffet_flutter` owns** the guide and anything describing client behaviour.
- **`buffet_app` owns** `docs/contracts/*.cs`, which are copied *from* the backend, verbatim.
- A change to a shared document has to be made in both, in the same change.

## Convention

A request document carries its outcome in its own header — `**Resolved:** <date>` — and moves here
once it is true. Do not delete one: the reasoning outlives the request, and a question that was
already answered gets asked again if the answer is thrown away.
