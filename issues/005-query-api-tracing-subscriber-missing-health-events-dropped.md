# 005 — `query-api` and `kaleidoscope-gateway` have no tracing subscriber: pre-spawn structured events are dropped silently

- Status: `open`
- Expectations affected: Q01 (asserts on stderr text rather
  than `health.startup.refused`), G01 (asserts on aperture's
  post-spawn `event=ready` rather than `gateway_starting`).
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
