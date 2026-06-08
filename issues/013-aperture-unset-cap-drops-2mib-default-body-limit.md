# 013 — aperture's unset/no-cap HTTP path drops axum's 2 MiB DefaultBodyLimit

- Status: `resolved` (2026-06-08). Grounded RED by **A23** at kaleidoscope HEAD
  `cd567e0`; FIXED in `88ef2aa` (aperture-body-size-cap-v0 fix-forward) — the
  unset/no-cap HTTP path now falls back to a restored 2 MiB bound
  (`const DEFAULT_HTTP_BODY_LIMIT_BYTES = 2 * 1024 * 1024`), so an oversized
  body is refused 413 before the sink, matching the pre-feature `Bytes`
  `DefaultBodyLimit`. **A23 flipped GREEN at `1f60ff5`**: 20 MiB → 413, small
  bodies still pass, boundary byte-exact (2097152 → 400 inclusive, 2097153 →
  413). The false "byte-for-byte today's behaviour" doc-comment is corrected to
  describe the 2 MiB fallback, with a drift-guard `assert_eq!`. The implementer
  fixed the behaviour AND the prose, not just the symptom.
  **Note:** the SEPARATE config-reachability facet originally raised here (a
  TOML-set `max_recv_msg_size` is still ignored because `into_config` does not
  wire it) is NOT addressed by `88ef2aa` and is split to
  [`issue 014`](014-aperture-toml-max-recv-msg-size-not-wired.md) / **A24**.
- Was: `open` (2026-06-08), grounded RED by **A23** at HEAD `cd567e0`
  (aperture-body-size-cap-v0 deliver `7138b88`/`7313f0b`).
- Severity: medium (availability / DoS-surface regression + a false design-
  decision claim). The new feature, on its only operator-reachable
  configuration path, makes the body-size posture STRICTLY WEAKER than the
  version it shipped on top of, and a code comment asserts the opposite of the
  observed behaviour.
- Surface: `crates/aperture` HTTP OTLP ingest, the unset/no-cap body path
  (`body_size_cap.rs` `collect_full_body` / `read_http_body_within_cap`,
  `config/mod.rs` `into_config`).
- Opened: 2026-06-08
- Source: the implementer invited the attack (msg 033) and flagged the unset
  HTTP path as something she had NOT verified: "if it is accepted, that is a
  regression in the unset default I owe a fix for." Confirmed black-box by the
  verifier.

## The gap

aperture-body-size-cap-v0 moved the HTTP ingest handlers from the buffered
`axum::body::Bytes` extractor (which carries axum's built-in **2 MiB
`DefaultBodyLimit`**) to a streaming `axum::body::Body`. The feature's design
decision DD2/C2 states the unset/no-cap path is unchanged — `body_size_cap.rs`
says it is "byte-for-byte today's behaviour" and "mirrors axum's default
`Bytes` extraction" (lines 6-7, 100, 135-137). It is not: the streaming path
applies no body limit, and no `DefaultBodyLimit` layer remains in the tree.

Compounding it: `RawConfig::into_config` (`config/mod.rs:645+`) never calls
`.max_recv_msg_size()`, and there is no top-level `max_recv_msg_size` TOML
field — the enforced cap (`Config.max_recv_msg_size`) is settable ONLY via the
programmatic `Config::builder()` (used by the in-process slice_11 tests). So no
TOML-configured aperture — the only operator/harness deployment — can enable
the cap, and every one runs the now-unbounded no-cap path.

## Observed (black-box, A23 + differential)

Valid HS256 bearer, `Content-Type: application/x-protobuf`, POST `/v1/logs`,
stub-sink standalone aperture with a complete auth config and no cap:

| body | pre-feature parent `ad8436d` | HEAD `cd567e0` |
| --- | --- | --- |
| 100 B (control) | 400 | 400 |
| 3 MiB | **413** | **400** |
| 20 MiB | **413** | **400** |

The 100 B control is 400 on both (auth + content-type clear; malformed
protobuf), so the large-body divergence is body **size** alone. The parent
refuses >2 MiB at 413 (axum `DefaultBodyLimit`); HEAD accepts and fully
buffers 3 MiB and 20 MiB, reaching protobuf decode (400). No `body_too_large`
event on the no-cap path.

## What would make A23 pass

The unset/no-cap HTTP path again bounds an oversized body — i.e. a 20 MiB POST
is refused (413) rather than accepted-and-buffered — restoring the DD2/C2
"byte-for-byte today's behaviour" property. The fix shape is the implementer's
call: restore a default bound on the no-cap path, and/or wire a TOML cap that
`into_config` honours. A23 asserts the contract format-agnostically and flips
GREEN on either.

## Scope note (verifier)

Reported as a failing expectation about observable behaviour. Two distinct
facets, one root cause (the no-cap streaming path applies no limit): (1) the
default posture regressed versus the prior binary; (2) the `body_size_cap.rs`
"byte-for-byte today's behaviour" comment is false. The gRPC path and the
*set*-cap HTTP path (16-byte cap vs 100 B body, slice_11) are not implicated
by this issue and are not asserted here.
