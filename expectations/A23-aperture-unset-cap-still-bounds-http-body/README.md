# A23 — aperture-unset-cap-still-bounds-http-body

## Surface

`crates/aperture` HTTP OTLP ingest body handling, after
aperture-body-size-cap-v0 (deliver `7313f0b`).

## Behaviour

The feature moved the HTTP ingest handlers from the buffered
`axum::body::Bytes` extractor — which carries axum's built-in **2 MiB
`DefaultBodyLimit`** — to a streaming `axum::body::Body` collected by
`read_http_body_within_cap`. The feature's own design decision **DD2/C2**
states the unset / no-cap path is unchanged from before:

- `body_size_cap.rs:6-7` — "`None` (unset) = no cap = today's exact
  accept-and-ignore behaviour (DD2/C2)."
- `body_size_cap.rs:100` — "No cap (unset or 0): collect the full body
  exactly as today."
- `body_size_cap.rs:135-137` — "Collect a request body with no size cap (the
  unset path). **Mirrors axum's default `Bytes` extraction so the no-cap path
  is byte-for-byte today's behaviour**."

A23 asserts that observable contract: with **no cap configured**, an oversized
HTTP OTLP body is refused (413) before being fully buffered, exactly as the
pre-feature binary refused it.

## Source

- The feature's own DD2/C2 design decision and the `body_size_cap.rs`
  no-cap-path doc-comments (above) — this is the implementer's stated intent,
  asserted as observable behaviour, not an external contract.
- Implementer msg 033 explicitly flagged the unset HTTP path as unverified:
  "if it is accepted, that is a regression in the unset default I owe a fix
  for." A23 grounds that.

## Verification

- Status: `satisfied` (transition-proof flipped RED→GREEN).
- Verified GREEN: 2026-06-08 UTC at HEAD (`1f60ff5`, fix `88ef2aa`).
  - Control `100 B` body → `400` (auth + content-type clear; small body still
    passes the size gate — not over-rejected).
  - `20 MiB` body → **`413`** (refused, sink untouched). The no-cap path again
    bounds the body.
  - Boundary spot-check confirms the restored bound is **byte-for-byte** axum's
    2 MiB `DefaultBodyLimit`: `1.5 MiB → 400`, `2097152 (exactly 2 MiB) → 400`
    (inclusive), `2097153 (one over) → 413`, `2.5 MiB → 413`. Not
    over-corrected (small bodies pass) nor under-corrected (just-over refused).
  - The previously-false `body_size_cap.rs` doc-comment is corrected: the unset
    path now documents + enforces the 2 MiB fallback (`const
    DEFAULT_HTTP_BODY_LIMIT_BYTES = 2 * 1024 * 1024`, drift-guard `assert_eq!`),
    so prose and behaviour agree.
- Grounded RED: 2026-06-08 UTC at HEAD (`cd567e0`). Method: build aperture from
  the HEAD snapshot; boot with a complete valid ingest-auth config carrying
  **no** `max_recv_msg_size` (the unambiguous no-cap path), stub sink; mint a
  valid HS256 bearer; POST `/v1/logs` with `Content-Type:
  application/x-protobuf`. At `cd567e0` the `20 MiB` body returned `400`
  (accepted + fully buffered).
- Differential proof of the regression: the pre-feature parent `ad8436d`,
  same config + bearer + body, returned **`413`** for both 3 MiB and 20 MiB
  (axum's 2 MiB `Bytes` `DefaultBodyLimit`); `cd567e0` returned `400` for both.
  The fix `88ef2aa` restores parity. See
  [issue 013](../../issues/013-aperture-unset-cap-drops-2mib-default-body-limit.md)
  (resolved). The SEPARATE config-reachability facet (a TOML-set
  `max_recv_msg_size` is still ignored) is split to
  [issue 014](../../issues/014-aperture-toml-max-recv-msg-size-not-wired.md) /
  **A24**.

## Evidence

- [`evidence/codes.txt`](evidence/codes.txt) — `small_100B=400`,
  `body_20MB=400` at `cd567e0`.
- [`evidence/aperture.stderr.txt`](evidence/aperture.stderr.txt) — no
  `body_too_large` event (the no-cap path emits none).

## Issues

[013](../../issues/013-aperture-unset-cap-drops-2mib-default-body-limit.md) —
the unset/no-cap HTTP path dropped axum's 2 MiB `DefaultBodyLimit`, so a
TOML-configured aperture (the only operator-reachable deployment, since
`into_config` never wires the top-level cap) now accepts and fully buffers an
arbitrarily large body where the prior version refused it at 413. Weaker
default posture; the feature's "before the full body is buffered" guarantee is
defeated on the unset path.

## Notes

`.no-compose`, A22-style self-contained run. Transition-proof: format-agnostic
on the fix — flips GREEN whether the no-cap path restores a default bound or a
TOML cap is wired and honoured, because either makes a 20 MiB body → 413.
