# 005 — `query-api` and `kaleidoscope-gateway` have no tracing subscriber: pre-spawn structured events are dropped silently

- Status: `partial` — the READ tier (query-api, log-query-api,
  trace-query-api) is FIXED at `2663eb5`; `kaleidoscope-gateway`
  still has no subscriber (see "Remaining" below).
- Expectations affected: Q01 (now asserts the structured
  `health.startup.refused`, tightened at `2663eb5`), LQ06 + TQ04
  (new, assert the same on the log/trace read binaries), G01
  (still asserts on aperture's post-spawn `event=ready` — gateway
  part unresolved).

## Resolution — read tier (2026-06-01, HEAD 2663eb5)

read-api-tracing-subscriber-v0 landed (feat `2663eb5`,
"shared init_tracing makes the read tier observable"). A shared
`query_http_common::init_tracing` installs a JSON-to-stderr tracing
subscriber (EnvFilter on RUST_LOG, OnceLock-guarded); all three read
binaries call it on the first line of main. Black-box confirmed: the
fail-closed arm now emits a structured JSON event on stderr before the
non-zero exit, observed verbatim:

  query-api  (Q01):  {"level":"ERROR","event":"health.startup.refused",
                      "reason":"KALEIDOSCOPE_QUERY_TENANT is unset or empty (fail-closed)"}
  log-query-api (LQ06): ...KALEIDOSCOPE_LOG_QUERY_TENANT...
  trace-query-api (TQ04): ...KALEIDOSCOPE_TRACE_QUERY_TENANT...

Q01 was tightened from the bare `Err()` text onto a `jq`-parsed
assertion of `event==health.startup.refused` / `level==ERROR` / reason.
LQ06 and TQ04 are new and assert the same from the start. The
`*_starting` and `listener_bound` info events also now reach stderr
(the empty-container-stderr note on LQ02/LQ03/TQ01 is no longer true).

## Remaining — gateway tier (still open)

`crates/kaleidoscope-gateway/src/main.rs` at `2663eb5` STILL installs
no subscriber (verified: no `init_tracing` / `tracing_subscriber` call;
the feat touched only query-http-common + the three read main.rs). So
the gateway's `gateway_starting` / `listener_bound` events are still
dropped, and G01 still asserts on aperture's post-spawn `event=ready`
rather than the gateway's own structured startup event. Flagged to Bea
Implementer as a follow-up slice (the gateway is a fourth binary with
the same gap; read-api-tracing-subscriber-v0 was deliberately scoped to
the read APIs). This issue stays `partial` until the gateway gets the
same `init_tracing` posture.

----------------------------------------------------------------
Original report
----------------------------------------------------------------
- Opened: 2026-05-24
- Kaleidoscope SHA at observation: `0c1d66b560ad48f5822d2fd30d00b41045368ec0`

## Observed

`crates/query-api/src/main.rs` emits structured tracing events
for lifecycle decisions, e.g.

```rust
tracing::info!(event = "query_api_starting", ...);
tracing::error!(event = "health.startup.refused", reason = %reason);
```

ADR-0042 DD9 promises an operator-visible refusal signal on the
Earned-Trust path. But `main()` installs no tracing subscriber:
`grep -n 'tracing_subscriber\|subscriber' crates/query-api/src/main.rs`
returns nothing.

Without a subscriber, every `tracing::info!` and
`tracing::error!` event is dropped. The operator-visible
signal is reduced to the `Err(_)` line that Rust's default
Result-from-main prints, e.g.

```
Error: "KALEIDOSCOPE_QUERY_TENANT is unset or empty (fail-closed)"
```

That is enough to verify Q01's fail-closed contract (the
catalogue runner asserts on this line), but it is a softer
contract than ADR-0042 advertises and it leaves no observable
trace for `query_api_starting`, `health.startup.refused`, or
any future structured lifecycle event.

## Expected

Each composition-root `main()` installs a tracing subscriber
(`tracing_subscriber::fmt` or similar) BEFORE the first
`tracing::info!` / `tracing::error!` call, so the events the
code emits are actually visible to an operator running the
container.

This affects both:

- `crates/query-api/src/main.rs` — emits
  `query_api_starting` and `health.startup.refused`, both
  dropped.
- `crates/kaleidoscope-gateway/src/main.rs` — emits
  `gateway_starting` and `health.startup.refused`, both
  dropped because the subscriber is only installed when
  `aperture::spawn` is reached.

(`crates/aperture/src/main.rs` — the standalone aperture
binary — gets it right: aperture's compose installs the
subscriber and any pre-init failure prints to stderr directly
via `eprintln!`. The new binaries should match that posture
explicitly.)

## Reproduction

```bash
docker run --rm -v "$(mktemp -d):/data" -e RUST_LOG=info \
    kaleidoscope-expectations/query-api:under-test 2>&1
# Single line of output: Error: "KALEIDOSCOPE_QUERY_TENANT is unset or empty (fail-closed)"
# No health.startup.refused event, no query_api_starting event.
```

## Catalogue impact

Q01 stays GREEN against an underspecified surface. When the
subscriber lands, the runner should tighten: assert
`event=health.startup.refused` (or whichever shape the
subscriber uses) on stderr, rather than the bare `Err(...)`
text. Track the upgrade alongside the fix.

## Addendum (cycle 31, 2026-05-29, HEAD 35c314a)

The same defect is now confirmed in a SECOND binary:
`crates/log-query-api/src/main.rs` emits `log_query_api_starting`
and `listener_bound` via `tracing::info!` and a
`health.startup.refused` via `tracing::error!`, but installs no
subscriber, so all three are dropped. LQ01's evidence
`log-query-api.stderr.txt` is empty for exactly this reason. LQ01
sidesteps it by asserting on the HTTP status + body, but a future
LQ fails-closed-no-tenant expectation will hit the same wall Q01
did and should assert on the bare `Err(...)` text until the
subscriber lands. The "new binaries should match aperture's
posture" point above now covers query-api AND log-query-api;
trace-query-api is likely a third instance (unverified).
