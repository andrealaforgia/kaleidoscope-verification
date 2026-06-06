# Q10 — query-api-label-matcher-variants

## Surface

`crates/query-api` binary (`/api/v1/query_range` PromQL label matchers),
via the gateway → Pulse → query-api round-trip.

## Behaviour

Over two series of metric `gen` differing by labels (`job=x,env=prod` and
`job=y,env=dev`), query-api honours the full label-matcher set:
- inequality: `gen{job!="x"}` → only the `y` series (UC-MET-003);
- regex: `gen{job=~"x.*"}` → only the `x` series (UC-MET-004);
- negated regex: `gen{job!~"x.*"}` → only the `y` series (UC-MET-005);
- multiple matchers AND together: `gen{job="x",env="prod"}` → the `x`
  series; `gen{job="x",env="dev"}` → empty (both must match, UC-MET-006).

## Source

- External contract anchor: query-api PromQL selector evaluation over
  Pulse labels.
- Use-case anchor: `kaleidoscope-usecases` UC-MET-003/004/005/006.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`bb33b95`).
- Method: ingest `gen` twice with distinct `job`/`env` data-point
  attributes; assert each matcher selects the right series and the AND of
  two matchers narrows / empties correctly.

## Evidence

- [`evidence/q-neq.json`](evidence/q-neq.json), [`evidence/q-regex.json`](evidence/q-regex.json), [`evidence/q-negregex.json`](evidence/q-negregex.json), [`evidence/q-and_match.json`](evidence/q-and_match.json), [`evidence/q-and_nomatch.json`](evidence/q-and_nomatch.json).

## Issues

None.

## Notes

`.no-compose`; built via `harness/run-eg.sh`. Extends Q06 (`__name__`
equality) to the full matcher set. Metric labels come from telemetrygen
`--telemetry-attributes`. UC-MET-008 (half-open window) is the remaining
buildable gap (needs points at exact boundary timestamps).
