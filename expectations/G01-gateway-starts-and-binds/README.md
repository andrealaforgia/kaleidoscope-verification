# G01 — gateway-starts-and-binds

## Surface

`kaleidoscope-gateway` operator binary (OTLP/gRPC :4317,
OTLP/HTTP/protobuf :4318). Operator-facing.

## Behaviour

`kaleidoscope-gateway` started with a writable pillar root and
`KALEIDOSCOPE_DEFAULT_TENANT` set comes up healthy: the
storage-sink probe passes, aperture (which the gateway
delegates to via `aperture::spawn`) binds OTLP/gRPC :4317 +
OTLP/HTTP :4318, and emits `event=ready` on stderr within a
short window. This is the Earned-Trust positive path from
ADR-0041 DD5.

The gateway's own `tracing::info!(event="gateway_starting")`
in `crates/kaleidoscope-gateway/src/main.rs` is dropped on the
floor because main.rs installs no tracing subscriber and
aperture installs one only post-spawn — see issue 005. We
therefore assert on aperture's `event=ready`, which fires
AFTER the subscriber is up.

## Source

- External contract anchor:
  [`ADR-0041`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0041-aperture-storage-sink-translation-and-tenancy.md)
  DD5 ("wire → probe → use; gateway refuses startup if the sink
  probe fails").
- Code: `crates/kaleidoscope-gateway/src/main.rs` (`tracing::info!(event = "gateway_starting", ...)` and the
  `sink.probe().await` arm).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-24 UTC at HEAD (`0c1d66b`).
- Method: `harness/run-gateway.sh` builds the gateway runtime
  image from the snapshot's `Dockerfile.gateway`. A `docker
  run -d` brings the container up with /data writable +
  DEFAULT_TENANT=acme; the runner polls the container's stderr
  for `gateway_starting` for up to 30 s; then SIGTERMs the
  container. Asserts the event was observed.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/G01.stdout.txt`](evidence/G01.stdout.txt) — runner trace.
- [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt) — the gateway's stderr (the startup event lives here).

## Issues

- [issue 005](../../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md)
  — same pattern as query-api: the gateway's `main.rs` emits
  `tracing::info!(event="gateway_starting")` and
  `tracing::error!(event="health.startup.refused")` but
  installs no subscriber, so both events are dropped. Once a
  subscriber lands, this runner should tighten to assert the
  `gateway_starting` event before the `ready` event.

## Notes

`.no-compose` marker — the gateway is the compose target, not
a downstream component, so we run it directly rather than via
the harness's docker-compose stack.

G01 is a smoke contract: it does NOT exercise OTLP ingest yet.
Subsequent G expectations should cover gateway accepting traces
/ logs / metrics and persisting them to the pillars, then a
round-trip via Q-prefix (read side) and K-prefix (CLI).
