# A16 — post-init-lifecycle-via-tracing

## Surface

Aperture (OTLP ingest gateway). Operator-facing.

## Behaviour

Post-init, every lifecycle event aperture emits is a complete JSON
line on stderr produced by the `tracing` /
`tracing-subscriber` JSON layer, with at minimum a `timestamp`,
`level`, and `event` field. Per ADR-0009 the layer is configured
with `with_target(false)`, `with_current_span(false)`, and
`with_span_list(false)`, so no `target` field, no `span` field,
no `spans` field appears in the output.

The source feed for this item said "target=\"aperture\""; that
contradicts ADR-0009. The catalogue trusts the ADR (committed,
external) over the inter-session feed.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **A16**
  (with the target-field clause overridden by the ADR).
- External contract anchor:
  [`docs/product/architecture/adr-0009-aperture-observability-strategy.md`](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/docs/product/architecture/adr-0009-aperture-observability-strategy.md)
  lines 13, 25, 34 (JSON layer to stderr; one event per line; level + timestamp + event-name; with_target(false), with_current_span(false), with_span_list(false)).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-06T23:32 UTC
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: the runner waits for aperture ready, snapshots its full
  container stderr, and parses each line with `jq`. It asserts:
  every line is valid JSON; every line carries `timestamp`,
  `level`, `event`; no line carries a `target`, `span`, or `spans`
  field. Counts are reported in
  `evidence/json-shape-report.txt`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/aperture.live.stderr.txt`](evidence/aperture.live.stderr.txt) — five lifecycle lines: startup, listener_bound (grpc), listener_bound (http), readiness_changed, ready.
- [`evidence/json-shape-report.txt`](evidence/json-shape-report.txt) — verbatim:
  ```
  lines_total:         5
  lines_bad_json:      0
  lines_missing_field: 0
  lines_with_target:   0 (ADR-0009 with_target(false): expected 0)
  lines_with_span:     0 (ADR-0009 with_current_span/with_span_list(false): expected 0)
  ```

## Issues

None.

## Notes

This expectation deliberately contradicted the source feed where
the source feed contradicted the committed ADR. The catalogue's
methodology rule 3 ("inter-session feeds are claims, not contracts")
applies: the ADR is the contract; the feed text is annotated.
