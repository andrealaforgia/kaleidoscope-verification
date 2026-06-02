# G01 — gateway-starts-and-binds

## Surface

`kaleidoscope-gateway` operator binary (OTLP/gRPC :4317,
OTLP/HTTP/protobuf :4318). Operator-facing.

## Behaviour

`kaleidoscope-gateway` started with a writable pillar root and
`KALEIDOSCOPE_DEFAULT_TENANT` set comes up healthy and announces its OWN
structured lifecycle on stderr, in order:

```
{"level":"INFO","event":"gateway_starting","pillar_root":"/data"}
{"level":"INFO","event":"listener_bound","transport":"grpc","addr":"0.0.0.0:4317"}
{"level":"INFO","event":"listener_bound","transport":"http","addr":"0.0.0.0:4318"}
```

G01 asserts that `gateway_starting` and the http `listener_bound` are
both structured JSON at INFO level, and that `gateway_starting` is
emitted BEFORE `listener_bound`.

## Source

- gateway-tracing-subscriber-v0 (feat `caa8cdf`, "early tracing
  subscriber makes gateway lifecycle observable"): the gateway now
  installs a JSON-to-stderr subscriber early in `main`, before any
  event, so its own lifecycle events render.
- Code: `crates/kaleidoscope-gateway/src/main.rs`
  (`init_tracing()` at the top of main; `tracing::info!(event =
  "gateway_starting", ...)` then aperture's `listener_bound`).

## Verification

- Status: `satisfied`
- Last verified: 2026-06-02 UTC at HEAD (`b286cb4`, clean tree;
  includes the gateway subscriber feat `caa8cdf`) — TIGHTENED onto the
  gateway's own structured events. GREEN after a catalogue-side fix (the
  first `listener_bound` is `transport=grpc`; the http assertion now
  targets the http line specifically).
- Earlier `satisfied`: 2026-05-24 at `0c1d66b`, asserting on aperture's
  post-spawn `event=ready` because the gateway's own events were dropped
  (no subscriber; issue 005, now resolved).
- Method: `harness/run-gateway.sh` builds the gateway image; `docker
  run -d` brings it up with /data writable + DEFAULT_TENANT=acme,
  publishing :4318 to a UNIQUE high host port (`14329`) so a parallel
  dev-side `kaleidoscope-e2e` compose stack squatting `4317-4318` does
  not collide (N27). The runner polls the container stderr for
  `listener_bound`, then asserts the two structured events + their
  order.

## The ordering gap

issue 005's gateway half was an ORDERING gap, not just a missing
subscriber: `gateway_starting` was emitted before `aperture::spawn`
installed its subscriber and was therefore dropped, while
`listener_bound` (emitted by aperture after its install) already
rendered. The early-install fix makes `gateway_starting` render too,
and G01 now pins the order (`gateway_starting` before `listener_bound`)
as the regression guard for that exact gap.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `b286cb4`.
- [`evidence/G01.stdout.txt`](evidence/G01.stdout.txt) — runner trace.
- [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt) — the
  gateway's structured JSON lifecycle events.

## Issues

None. G01 is part of the evidence that closed the gateway half of
[issue 005](../../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md)
(now `resolved`). Note: the gateway's `health.startup.refused`
(fsync-probe refusal arm) is NOT black-box triggerable here — a
read-only `/data` fails earlier at store-open (G02), and the probe arm
needs a lying-fsync substrate; it is covered by the implementer's own
acceptance test. See issue 005.

## Notes

`.no-compose` marker — the gateway is the compose target, not a
downstream component, so we run it directly. Unique high host port
(`14329`) per N27. G01 is a smoke + lifecycle contract; OTLP
round-trips are covered by EG01 (metrics) and the D-prefix (durability).
