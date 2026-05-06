# E06 — sigterm-during-emit-bounded-flush

## Surface

End-to-end (Spark + Aperture, loopback). integrator-facing.

## Behaviour

An app receiving SIGTERM mid-emission triggers SparkGuard's bounded flush; tracing events on stderr surface the outcome; Aperture sees in-flight payloads land within the deadline.

The full Given/When/Then contract is to be tightened during pilot
verification against the external anchor identified below.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **E6**.
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
harness/run-expectation.sh E06
```

and stored under [`evidence/`](evidence/) (`verification.yaml`,
`aperture.stderr.txt`, `otelcol-sink.stderr.txt`,
`otlp-received.jsonl`, plus any expectation-specific captures
named by the runner).

## Issues

None.

## Notes

None.
