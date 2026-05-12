# SI02 — sieve-non-error-rate-statistical

## Surface

Sieve (head-based sampling decorator). Operator/integrator-facing,
via aperture's pipeline when ADR-0021's `SamplingSink` decorator
is wired.

## Behaviour

When a sampling rule is configured with rate r (0 < r < 1), the proportion of non-error spans kept converges to r within a documented tolerance. The decision is deterministic in trace_id via xxh3_64 (SI03).

## Source

- External contract anchor:
  [`docs/feature/sieve/slices/slice-03-non-error-rate.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/feature/sieve/slices/slice-03-non-error-rate.md)
  and
  [`docs/product/architecture/adr-0021-sieve-aperture-integration.md`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/docs/product/architecture/adr-0021-sieve-aperture-integration.md).

## Verification

- Status: `pending`
- Last verified: never (catalogue placeholder; see known-gaps.md N8).
- Method: TBD. Two paths exist:
  (a) aperture wires the `SamplingSink` decorator from
  `aperture.toml` and the harness exercises it in compose;
  (b) a sieve-consumer fixture (similar to `harness/spark-consumer`)
  links `crates/sieve` and exercises the decorator in-process. At
  HEAD neither is in place.

## Evidence

None yet.

## Issues

None.

## Notes

This stub exists to make the Sieve surface visible in the
catalogue. Without harness wiring, the contract is observable
only via kaleidoscope's own integration tests (`crates/sieve/tests`),
which is internal verification per the project's CI gates.
