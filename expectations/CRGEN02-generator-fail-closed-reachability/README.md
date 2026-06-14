# CRGEN02 — generator-fail-closed-reachability

## Surface

The first-party generator's mandatory pre-flight reachability probe
(`kaleidoscope-telemetrygen`, ADR-0077 F3). The fail-closed "never emit into the
void" contract — the attack the implementer asked be hit hardest.

## Behaviour

Pointed at an unreachable ingest endpoint, the generator runs a bounded TCP
reachability probe BEFORE any emit and refuses: non-zero exit, the unreachable
endpoint NAMED on stderr with a clear reason and remediation, and ZERO bytes
emitted.

A live runtime is up so "emitted nothing" is checkable against its stores, but
the generator is pointed at a CLOSED port (:4399) on it. Observed stderr:

```
kaleidoscope-telemetrygen: ingest endpoint http://<rt>:4399 is unreachable
(Connection refused (os error 111)); bring the stack up first (for example
`make up`) before generating telemetry
```

and all three runtime stores stay empty.

## Source

- kaleidoscope generator deliver `4eacfb8` (slice 2), HEAD `3658376`; the
  `probe_reachable` seam runs before `spark::init` / any export.

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at committed HEAD `3658376`. Generator exit
  non-zero; stderr names `:4399` + "unreachable … bring the stack up"; after the
  failed probe the runtime stores are empty (metrics 0 series, logs 0 records,
  by-id 0 spans) — nothing leaked past the gate.
- Method: build runtime + generator from the HEAD snapshot, network them, point
  the generator at a closed port on the runtime, assert exit + named reason +
  empty stores.

## Notes

`.no-compose`. The differential partner is CRGEN01, where the SAME generator
invocation against the LIVE endpoint emits all three signals (exit 0). Together
they prove the probe discriminates live vs dead, not a guess.
