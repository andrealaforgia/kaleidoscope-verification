# S10 — reinit-after-drop-allowed

## Surface

Spark (auto-instrumentation SDK). integrator-facing.

## Behaviour

After dropping the first guard, a subsequent spark::init returns Ok(...) again. Sequential init→drop→init is permitted at v0.6 of the slice.

The full Given/When/Then contract is to be tightened during pilot
verification against the external anchor identified below.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **S10**.
- External contract anchor: **TBD**. Candidates to inspect, in this order:
  1. `docs/feature/aperture/distill/wave-decisions.md`
  2. `docs/feature/aperture/distill/acceptance-test-coverage-matrix.md`
  3. `docs/feature/aperture/slices/` (the slice that owns this surface)
  4. `docs/product/architecture/adr-*.md` (the relevant ADR)

If no committed anchor exists at the time of verification, the expectation
is annotated `unanchored-claim` even when the binary passes.

## Verification

- Status: `pending`
- Last verified: never
- Kaleidoscope SHA: n/a
- Kaleidoscope dirty: n/a
- Method: TBD

## Evidence

None yet. Once verified, evidence is captured by:

```
harness/run-expectation.sh S10
```

and stored under [`evidence/`](evidence/) (`verification.yaml`,
`aperture.stderr.txt`, `otelcol-sink.stderr.txt`,
`otlp-received.jsonl`, plus any expectation-specific captures
named by the runner).

## Issues

None.

## Notes

None.
