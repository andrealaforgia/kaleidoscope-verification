# Q03 — query-api-step-accepted-but-ignored

## Surface

`query-api` `GET /api/v1/query_range`, the `step` query parameter.
Integrator-facing (Prometheus-compatible read contract, ADR-0042).

## Behaviour

Given one OTLP metric ingested via the gateway into Pulse and read back
through query-api
When `query_range` is called over a FIXED `[start,end]` window first with
`step=15s` and then with `step=3600s` (only `step` varies)
Then both calls succeed and return BYTE-IDENTICAL `.data.result`: `step`
has no effect on the series. query-api returns the raw stored points and
does not re-step at v0.

## This is disclosed, not a defect

The Prometheus `query_range` contract uses `step` to control sample
resolution, so an integrator might expect it to bucket or downsample.
query-api at v0 does not: `step` is `#[allow(dead_code)] step:
Option<String>` (`crates/query-api/src/lib.rs:144`) and the doc comment
states "`step` is accepted and ignored at v0 (DD5: raw points, no
re-stepping)". Because the behaviour is DISCLOSED in the contract, this
is a truthful v0 limitation, not a false claim like
[issue 008](../../issues/008-tls-enabled-claims-rejection-but-binds-plaintext.md).
Q03 is therefore a GREEN expectation pinning the disclosed behaviour, not
a filed issue.

## Integrator caveat (recorded honestly)

A Prometheus-compatible client (Grafana, a dashboard) that relies on
`step` to bucket or downsample will receive raw points regardless of the
value it sends. That is the observable consequence an integrator should
know. It is disclosed by DD5 and the pinned client (Prism) is built
against it; no remediation is implied. If v0 later implements
re-stepping, Q03's two responses will diverge and the runner fails loudly
(prompting a re-frame), so it doubles as the regression guard.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-04 UTC at HEAD (`ea72f1e`). GREEN: both
  `status=success`, 1 series, 2 raw samples, `.data.result` byte-identical
  between `step=15s` and `step=3600s`.
- Method: `harness/run-eg.sh` (gateway + query-api built from the HEAD
  snapshot). telemetrygen sends one counter `gen` to the gateway on a
  unique high port (14333); the gateway is SIGTERMed to flush Pulse;
  query-api reopens the same `/data` on port 19098; `query_range` is
  called twice over one fixed window varying only `step`; the two
  `.data.result` payloads are compared after `jq -S` canonicalisation.
  A non-empty series is required first, so identity cannot pass
  vacuously on an empty result.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `ea72f1e`.
- [`evidence/response-step-15s.json`](evidence/response-step-15s.json),
  [`evidence/response-step-3600s.json`](evidence/response-step-3600s.json)
  — the two responses (identical `.data.result`).
- [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt),
  [`evidence/query-api.stderr.txt`](evidence/query-api.stderr.txt).

## Notes

Third query-api expectation (after Q01 fail-closed-no-tenant, Q02
window-cap-honest-400). Completes the four-quadrants Q1 backlog item on
query-api `step`. Same gateway→Pulse→query-api path as EG01, reused to
isolate a single parameter's effect.
