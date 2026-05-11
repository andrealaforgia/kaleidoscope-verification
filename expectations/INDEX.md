# Expectations index

Live status table. Updated when an expectation moves between states.

| Status | Count |
|---|---|
| `pending` | 15 |
| `satisfied` | 38 |
| `partial` | 0 |
| `broken` | 0 |
| `unanchored-claim` | 0 |
| `out-of-scope` | 6 (H1-H6 — see [`../known-gaps.md`](../known-gaps.md)) |

Last index refresh: 2026-05-07.

All 17 satisfied expectations re-verified at SHA `c871b5852356b346b6c1fdc48b8be93514c27d2f`
via `harness/re-verify-all.sh`; zero regressions across the 14 commits
between the original satisfaction SHA (`6b09c0d`) and the re-verification
SHA. Per-expectation `evidence/verification.yaml` carries the latest
SHA. Each README's "Last verified" line names the original satisfaction
date for traceability; the re-verification log lives at
`harness/.re-verify-summary/<ID>.{ok,broken}.txt` (gitignored, regenerated
on demand).

Discovery walk on the same range surfaced a new candidate prefix:
**SI** (Sieve), now graduated through Slice 06. Sampling decisions
(rate-zero drop, non-error rate via xxh3_64), DEBUG per-decision
events, INFO summary timer, and the `SamplingSink` decorator
integration with Aperture (ADR-0021) are now observable surfaces.
Codex DISCUSS+DESIGN closed (ADR-0022 to ADR-0025); no code yet.

Original-batch dates:
- 2026-05-06: pilot (A01, A04, A10) at SHA `6b09c0d`.
- 2026-05-06: batch 2 (A02, A03, A05, A06, A08, A09, A11, A12, A13,
  A15, A16, X04, X07, X08) at SHA `6b09c0d`.
- 2026-05-07: re-verification of all 17 at SHA `c871b58`.
- 2026-05-07: re-verification of all 21 (after batch A) at SHA `c8d8a55`.
  18/21 green in the batched run; A01, A02, X01 needed individual
  retries for transient Docker Desktop VM pressure after the heavy
  cargo workloads. All 21 confirmed green at the same SHA on retry.

Open issues: none.
Closed:
[001 — aperture binary ignores --config](../issues/001-aperture-binary-ignores-config-flag.md) (`fixed` at `6b09c0d`);
[002 — env-var overrides not wired](../issues/002-env-var-overrides-not-wired-in-figment-loader.md) (`fixed` at `c8d8a55`);
[003 — gRPC backpressure load reproducibility](../issues/003-grpc-backpressure-load-reproducibility.md) (`wontfix`, catalogue tooling).

## Deferred (reason recorded)

These pending expectations have a known reason for not being verified
yet. The reason lives in this catalogue, not as silent inaction.

| ID | Reason |
|---|---|
| ~~**S01-S22**~~ | (consumer fixture landed 2026-05-11; S01, S06-S10 satisfied; S02-S05 and S11-S22 are pending per-scenario branches in `harness/spark-consumer/src/main.rs`.) |
| **E01-E06** | Round-trip Spark + Aperture. Same fixture as S, plus aperture chain. E01 essentially proven by S01's evidence (round-trip works); the catalogue still tracks E1-E6 as their own contracts. |
| **A07** | gRPC malformed-bytes rejection requires a raw OTLP/gRPC client that can send hand-crafted invalid wire bytes. `telemetrygen` only emits valid bytes; `grpcurl` needs the OTLP proto descriptors mounted (not in the runtime image). Needs a small Python or Rust client; not yet built. |
| **A14** | Drain-deadline-exceeded path requires a downstream that holds aperture's request handler open longer than `drain_deadline_ms`, then a SIGTERM. otelcol-sink is fast; needs a slow-loris HTTP server in the harness. Not yet built. |
| ~~**X01, X02, X03, X05**~~ | (now satisfied — see the X table.) |
| **X06** | CI gates green at the test SHA. Requires authenticated `gh` access against the kaleidoscope repo; not in this session. |

## A — Aperture (operator/integrator-facing)

| ID | Slug | Behaviour summary | Status |
|---|---|---|---|
| [A01](A01-otlp-grpc-traces-accepted/README.md) | otlp-grpc-traces-accepted | OTLP/gRPC traces on :4317 are acked; sink receives `ExportTraceServiceRequest` with original span_count. | `satisfied` |
| [A02](A02-otlp-grpc-logs-accepted/README.md) | otlp-grpc-logs-accepted | OTLP/gRPC logs on :4317 are acked; sink receives `ExportLogsServiceRequest`. | `satisfied` |
| [A03](A03-otlp-grpc-metrics-accepted/README.md) | otlp-grpc-metrics-accepted | OTLP/gRPC metrics on :4317 are acked; sink receives `ExportMetricsServiceRequest`. | `satisfied` |
| [A04](A04-otlp-http-protobuf-traces-accepted/README.md) | otlp-http-protobuf-traces-accepted | OTLP/HTTP/protobuf traces on :4318 — 200 OK; sink receives `ExportTraceServiceRequest`. | `satisfied` |
| [A05](A05-otlp-http-protobuf-logs-accepted/README.md) | otlp-http-protobuf-logs-accepted | OTLP/HTTP/protobuf logs on :4318 — 200 OK; sink receives `ExportLogsServiceRequest`. | `satisfied` |
| [A06](A06-otlp-http-protobuf-metrics-accepted/README.md) | otlp-http-protobuf-metrics-accepted | OTLP/HTTP/protobuf metrics on :4318 — 200 OK; sink receives `ExportMetricsServiceRequest`. | `satisfied` |
| [A07](A07-grpc-rejects-malformed-bytes/README.md) | grpc-rejects-malformed-bytes | Malformed gRPC bytes rejected with `INVALID_ARGUMENT` and a recognisable Rule. | `pending` (deferred — needs raw gRPC client harness) |
| [A08](A08-http-rejects-malformed-bytes/README.md) | http-rejects-malformed-bytes | Malformed HTTP bytes rejected with 400 and a descriptive body. | `satisfied` |
| [A09](A09-backpressure-rejects-overload/README.md) | backpressure-rejects-overload | Above `max_concurrent_requests`, gRPC returns `RESOURCE_EXHAUSTED`; HTTP returns 503 with `Retry-After`. | `satisfied` |
| [A10](A10-readyz-200-when-healthy/README.md) | readyz-200-when-healthy | `GET /readyz` returns 200 in normal operation. | `satisfied` |
| [A11](A11-sigterm-flips-readyz-503/README.md) | sigterm-flips-readyz-503 | On SIGTERM, `/readyz` flips to 503 within the documented bound. | `satisfied` |
| [A12](A12-sigterm-completes-inflight-and-exits-zero/README.md) | sigterm-completes-inflight-and-exits-zero | On SIGTERM, in-flight requests complete within `drain_deadline_ms`; exit code 0. | `satisfied` |
| [A13](A13-sigint-same-drain-orchestration/README.md) | sigint-same-drain-orchestration | On SIGINT, the same drain orchestration runs as for SIGTERM. | `satisfied` |
| [A14](A14-drain-deadline-exceeded-exit-one/README.md) | drain-deadline-exceeded-exit-one | If drain deadline expires with requests in flight, exit 1; stderr emits `event=drain_deadline_exceeded`. | `pending` (deferred — needs slow downstream) |
| [A15](A15-config-error-pre-init-exit-two/README.md) | config-error-pre-init-exit-two | Bad config at startup — stderr `aperture: config error: ...` (pre-tracing) and exit 2. | `satisfied` |
| [A16](A16-post-init-lifecycle-via-tracing/README.md) | post-init-lifecycle-via-tracing | Post-init, every lifecycle event travels via structured tracing on stderr. | `satisfied` |

## S — Spark (integrator-facing)

| ID | Slug | Behaviour summary | Status |
|---|---|---|---|
| [S01](S01-init-canonical-config-emits-span/README.md) | init-canonical-config-emits-span | `spark::init` with canonical config returns `Ok(SparkGuard)`; an emitted span reaches Aperture. | `satisfied` |
| [S06](S06-missing-service-name-errors/README.md) | missing-service-name-errors | Empty service.name → `Err(MissingRequiredAttribute { name: "service.name" })`. | `satisfied` |
| [S07](S07-missing-tenant-id-when-required-errors/README.md) | missing-tenant-id-when-required-errors | `require_tenant_id()` without `with_tenant_id` → `Err(MissingRequiredAttribute { name: "tenant.id" })`. | `satisfied` |
| [S08](S08-malformed-endpoint-errors/README.md) | malformed-endpoint-errors | Malformed endpoint URL → `Err(InvalidEndpoint)`. | `satisfied` |
| [S09](S09-double-init-while-guard-alive-errors/README.md) | double-init-while-guard-alive-errors | Second `spark::init` while first guard alive → `Err(GlobalAlreadyInitialised)`. | `satisfied` |
| [S10](S10-reinit-after-drop-allowed/README.md) | reinit-after-drop-allowed | Sequential init→drop→init returns `Ok` the second time. | `satisfied` |
| [S02](S02-service-name-on-resource/README.md) | service-name-on-resource | Resource carries `service.name` exactly as set on `for_service`. | `satisfied` |
| [S03](S03-tenant-id-on-resource-when-required/README.md) | tenant-id-on-resource-when-required | Resource carries `tenant.id` when `require_tenant_id` + `with_tenant_id`. | `satisfied` |
| [S04](S04-feature-flags-on-resource/README.md) | feature-flags-on-resource | Resource carries `feature_flag.{k}` per pair in `with_feature_flags`. | `satisfied` |
| [S05](S05-experiment-id-on-resource/README.md) | experiment-id-on-resource | Resource carries `experiment.id` from `with_experiment_id`. | `satisfied` |
| [S11](S11-cross-signal-resource-symmetry/README.md) | cross-signal-resource-symmetry | Traces, logs, metrics from one Spark carry an identical Resource set. | `satisfied` |
| [S22](S22-malformed-endpoint-from-env-errors/README.md) | malformed-endpoint-from-env-errors | Malformed `OTEL_EXPORTER_OTLP_ENDPOINT` → `Err(InvalidEndpoint)`. | `satisfied` |
| [S12-S21](.) | (see individual READMEs) | tracing → log routing (S12), counter → metric routing (S13), no-telemetry-on-telemetry filter (S14), shutdown event vocabulary (S15-S17), drop bounded by flush_timeout (S18), drop no-panic on dead downstream (S19), idempotent drop (S20), endpoint precedence (S21). | `pending` (consumer fixture in place; remaining scenarios mostly require capturing the consumer's own stderr or precise timing). |

## E — End-to-end (Spark + Aperture round-trip)

| ID | Slug | Behaviour summary | Status |
|---|---|---|---|
| [E01](E01-round-trip-trace/README.md) | round-trip-trace | Span from Spark-instrumented app reaches otelcol-sink. | `satisfied` |
| [E02](E02-round-trip-log/README.md) | round-trip-log | tracing::info from Spark-instrumented app reaches otelcol-sink as resourceLogs. | `satisfied` |
| [E03](E03-round-trip-metric/README.md) | round-trip-metric | Counter.add from Spark-instrumented app reaches otelcol-sink as resourceMetrics. | `satisfied` |
| [E04](E04-house-attributes-survive-round-trip/README.md) | house-attributes-survive-round-trip | All four house attributes survive end-to-end on Resource. | `satisfied` |
| [E05, E06](.) | (see individual READMEs) | Clean-exit final batch (E05 — implicitly covered by every passing E01-E04 run); SIGTERM-during-emit bounded flush (E06). | `pending` (E05 trivially yes from existing evidence; E06 needs SIGTERM injection on the consumer). |

## X — Operations / build / supply chain

| ID | Slug | Behaviour summary | Status |
|---|---|---|---|
| [X01](X01-cargo-test-workspace-green/README.md) | cargo-test-workspace-green | `cargo test --workspace --all-targets --locked` green on a fresh clone. | `satisfied` |
| [X02](X02-cargo-deny-green/README.md) | cargo-deny-green | `cargo deny --all-features check` green. | `satisfied` |
| [X03](X03-cargo-public-api-locked/README.md) | cargo-public-api-locked | Public API matches ADR-0001 / ADR-0011 (tool runs green; diff-vs-baseline form deferred). | `satisfied` |
| [X04](X04-cargo-build-release-produces-binary/README.md) | cargo-build-release-produces-binary | `cargo build --workspace --release` produces an executable `aperture`. | `satisfied` |
| [X05](X05-pre-commit-hook-green-on-clean-tree/README.md) | pre-commit-hook-green-on-clean-tree | `scripts/hooks/pre-commit` green on clean workspace. | `satisfied` |
| [X06](X06-ci-five-gates-green-at-test-sha/README.md) | ci-five-gates-green-at-test-sha | CI five gates green at the SHA verified. | `pending` (deferred — needs `gh` auth) |
| [X07](X07-license-manifests-correct/README.md) | license-manifests-correct | otlp-conformance-harness/spark = Apache-2.0; aperture = AGPL-3.0-or-later. | `satisfied` |
| [X08](X08-forbid-unsafe-code-in-spark-and-aperture/README.md) | forbid-unsafe-code-in-spark-and-aperture | `forbid(unsafe_code)` in spark and aperture lib.rs. | `satisfied` |
| [X09](X09-xtask-regenerate-codex-corpus-idempotent/README.md) | xtask-regenerate-codex-corpus-idempotent | Running `xtask regenerate-codex-corpus` on a clean tree produces zero diff vs committed corpus (ADR-0023). | `satisfied` |
