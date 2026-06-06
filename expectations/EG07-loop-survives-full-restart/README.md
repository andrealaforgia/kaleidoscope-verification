# EG07 — loop-survives-full-restart

## Surface

`crates/kaleidoscope-gateway` (write + graceful restart) → {Pulse, Lumen,
Ray} → the three read APIs. Loop-level durability.

## Behaviour

After populating all three pillars, the gateway is stopped and RESTARTED
on the same volume: it re-opens the already-populated pillars and comes
up healthy (re-emits its startup lifecycle to `ready`, no
corruption/refusal), and all three signals remain queryable. Covers
UC-LOOP-006 (loop survives a full restart).

Distinct from D01-D03 (ungraceful kill-9 recovery, per pillar): this is a
clean restart of the writer over an already-populated volume, verified at
the loop level across all three pillars at once.

## Source

- External contract anchor: gateway pillar re-open on restart (WAL +
  snapshot recovery) + the three read APIs over the recovered volume.
- Use-case anchor: `kaleidoscope-usecases` UC-LOOP-006.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`56b114c`).
- Method: populate metric+log+trace; stop the gateway; restart it on the
  same volume → it reaches `ready`; query-api (metric=1), log-query-api
  (log=4), trace-query-api (trace=6) all still return their signal.

## Evidence

- [`evidence/gateway-restart.stderr.txt`](evidence/gateway-restart.stderr.txt) — healthy re-open.
- [`evidence/metric.json`](evidence/metric.json), [`evidence/log.json`](evidence/log.json), [`evidence/trace.json`](evidence/trace.json).

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-eg.sh`. Composes EG05 (three pillars
one stream) with a writer restart. UC-LOOP-007 (Prism plot) is 🟡
(Playwright harness, N11); UC-LOOP-009 (incident triage) is partially
shown by EG05 + LQ09.
