# Expectations index

Live status table. Updated when an expectation moves between states.

| Status | Count |
|---|---|
| `pending` | 52 |
| `satisfied` | 0 |
| `partial` | 0 |
| `broken` | 0 |
| `unanchored-claim` | 0 |
| `out-of-scope` | 6 (H1-H6 — see [`../known-gaps.md`](../known-gaps.md)) |

Last index refresh: 2026-05-06 (initial scaffold; no verification has run).

Pilot batch (planned first verifications): **A01**, **A04**, **A10**.

---

## A — Aperture (operator/integrator-facing)

| ID | Slug | Behaviour summary | Status |
|---|---|---|---|
| [A01](A01-otlp-grpc-traces-accepted/README.md) | otlp-grpc-traces-accepted | OTLP/gRPC traces on :4317 are acked; sink receives `ExportTraceServiceRequest` with original span_count. | `pending` |
| [A02](A02-otlp-grpc-logs-accepted/README.md) | otlp-grpc-logs-accepted | OTLP/gRPC logs on :4317 are acked; sink receives `ExportLogsServiceRequest`. | `pending` |
| [A03](A03-otlp-grpc-metrics-accepted/README.md) | otlp-grpc-metrics-accepted | OTLP/gRPC metrics on :4317 are acked; sink receives `ExportMetricsServiceRequest`. | `pending` |
| [A04](A04-otlp-http-protobuf-traces-accepted/README.md) | otlp-http-protobuf-traces-accepted | OTLP/HTTP/protobuf traces on :4318 — 200 OK; sink receives `ExportTraceServiceRequest`. | `pending` |
| [A05](A05-otlp-http-protobuf-logs-accepted/README.md) | otlp-http-protobuf-logs-accepted | OTLP/HTTP/protobuf logs on :4318 — 200 OK; sink receives `ExportLogsServiceRequest`. | `pending` |
| [A06](A06-otlp-http-protobuf-metrics-accepted/README.md) | otlp-http-protobuf-metrics-accepted | OTLP/HTTP/protobuf metrics on :4318 — 200 OK; sink receives `ExportMetricsServiceRequest`. | `pending` |
| [A07](A07-grpc-rejects-malformed-bytes/README.md) | grpc-rejects-malformed-bytes | Malformed gRPC bytes rejected with `INVALID_ARGUMENT` and a recognisable Rule. | `pending` |
| [A08](A08-http-rejects-malformed-bytes/README.md) | http-rejects-malformed-bytes | Malformed HTTP bytes rejected with 400 and a descriptive body. | `pending` |
| [A09](A09-backpressure-rejects-overload/README.md) | backpressure-rejects-overload | Above `max_concurrent_requests`, gRPC returns `RESOURCE_EXHAUSTED`; HTTP returns 503 with `Retry-After`. | `pending` |
| [A10](A10-readyz-200-when-healthy/README.md) | readyz-200-when-healthy | `GET /readyz` returns 200 in normal operation. | `pending` |
| [A11](A11-sigterm-flips-readyz-503/README.md) | sigterm-flips-readyz-503 | On SIGTERM, `/readyz` flips to 503 within the documented bound. | `pending` |
| [A12](A12-sigterm-completes-inflight-and-exits-zero/README.md) | sigterm-completes-inflight-and-exits-zero | On SIGTERM, in-flight requests complete within `drain_deadline_ms`; exit code 0. | `pending` |
| [A13](A13-sigint-same-drain-orchestration/README.md) | sigint-same-drain-orchestration | On SIGINT, the same drain orchestration runs as for SIGTERM. | `pending` |
| [A14](A14-drain-deadline-exceeded-exit-one/README.md) | drain-deadline-exceeded-exit-one | If drain deadline expires with requests in flight, exit 1; stderr emits `event=drain_deadline_exceeded`. | `pending` |
| [A15](A15-config-error-pre-init-exit-two/README.md) | config-error-pre-init-exit-two | Bad config at startup — stderr `aperture: config error: ...` (pre-tracing) and exit 2. | `pending` |
| [A16](A16-post-init-lifecycle-via-tracing/README.md) | post-init-lifecycle-via-tracing | Post-init, every lifecycle event travels via structured tracing on stderr with `target="aperture"`. | `pending` |

## S — Spark (integrator-facing)

| ID | Slug | Behaviour summary | Status |
|---|---|---|---|
| [S01](S01-init-canonical-config-emits-span/README.md) | init-canonical-config-emits-span | `spark::init` with canonical config returns `Ok(SparkGuard)`; an emitted span reaches Aperture. | `pending` |
| [S02](S02-service-name-on-resource/README.md) | service-name-on-resource | Resource carries `service.name` exactly as set on `SparkConfig::for_service(name)`. | `pending` |
| [S03](S03-tenant-id-on-resource-when-required/README.md) | tenant-id-on-resource-when-required | With `require_tenant_id()` + `with_tenant_id(id)`, Resource carries `tenant.id`. | `pending` |
| [S04](S04-feature-flags-on-resource/README.md) | feature-flags-on-resource | For each `(key, value)` in `with_feature_flags(...)`, Resource carries `feature_flag.{key} = value`. | `pending` |
| [S05](S05-experiment-id-on-resource/README.md) | experiment-id-on-resource | `with_experiment_id(id)` puts `experiment.id` on Resource. | `pending` |
| [S06](S06-missing-service-name-errors/README.md) | missing-service-name-errors | Without `service.name`, init returns `Err(MissingRequiredAttribute { name: "service.name" })`. | `pending` |
| [S07](S07-missing-tenant-id-when-required-errors/README.md) | missing-tenant-id-when-required-errors | With `require_tenant_id()` but no `tenant.id`, init returns `Err(MissingRequiredAttribute { name: "tenant.id" })`. | `pending` |
| [S08](S08-malformed-endpoint-errors/README.md) | malformed-endpoint-errors | Malformed endpoint returns `Err(InvalidEndpoint { endpoint, reason })`. | `pending` |
| [S09](S09-double-init-while-guard-alive-errors/README.md) | double-init-while-guard-alive-errors | A second `spark::init` while the first guard is alive returns `Err(GlobalAlreadyInitialised)`. | `pending` |
| [S10](S10-reinit-after-drop-allowed/README.md) | reinit-after-drop-allowed | After dropping the first guard, a subsequent `spark::init` returns `Ok(...)` again (sequential init→drop→init permitted at v0.6). | `pending` |
| [S11](S11-cross-signal-resource-symmetry/README.md) | cross-signal-resource-symmetry | Traces, logs, and metrics from the same app carry an identical Resource attribute set. | `pending` |
| [S12](S12-tracing-info-arrives-as-log-record/README.md) | tracing-info-arrives-as-log-record | `tracing::info!(target: "<app-target>", ...)` reaches Aperture as `ExportLogsServiceRequest`. | `pending` |
| [S13](S13-counter-arrives-as-metric-export/README.md) | counter-arrives-as-metric-export | A counter `add(1, &[])` reaches Aperture as `ExportMetricsServiceRequest` after flush. | `pending` |
| [S14](S14-spark-internal-target-not-forwarded/README.md) | spark-internal-target-not-forwarded | `tracing::info!(target: "spark", ...)` does NOT reach the sink as a LogRecord (no-telemetry-on-telemetry filter). | `pending` |
| [S15](S15-shutdown-initiated-tracing-event/README.md) | shutdown-initiated-tracing-event | `SparkGuard::Drop` emits a tracing INFO with `target="spark"` and message `"shutdown initiated flush_timeout_ms=N"`. | `pending` |
| [S16](S16-clean-shutdown-complete-event/README.md) | clean-shutdown-complete-event | On clean flush, INFO `"shutdown complete drained=unknown"` (`drained=` prefix is the contract; see N5). | `pending` |
| [S17](S17-deadline-exceeded-warn-event/README.md) | deadline-exceeded-warn-event | On expired deadline, WARN `"flush deadline exceeded dropped=unknown flush_timeout_ms=N"`. | `pending` |
| [S18](S18-drop-bounded-by-flush-timeout/README.md) | drop-bounded-by-flush-timeout | Total drop time is bounded by `flush_timeout` (default 5 s); never blocks indefinitely. | `pending` |
| [S19](S19-drop-no-panic-on-dead-downstream/README.md) | drop-no-panic-on-dead-downstream | Drop does NOT panic if the downstream is dead; terminates within the deadline. | `pending` |
| [S20](S20-second-drop-is-noop/README.md) | second-drop-is-noop | A second explicit `drop(guard)` is idempotent. | `pending` |
| [S21](S21-endpoint-precedence-builder-env-default/README.md) | endpoint-precedence-builder-env-default | Endpoint precedence: builder `with_endpoint` > `OTEL_EXPORTER_OTLP_ENDPOINT` > default `http://127.0.0.1:4317`. | `pending` |
| [S22](S22-malformed-endpoint-from-env-errors/README.md) | malformed-endpoint-from-env-errors | Malformed endpoint from env var returns `Err(InvalidEndpoint)` with the same shape as the builder case. | `pending` |

## E — End-to-end (Spark + Aperture round-trip)

| ID | Slug | Behaviour summary | Status |
|---|---|---|---|
| [E01](E01-round-trip-trace/README.md) | round-trip-trace | Spark-instrumented app emits a span; Aperture receives it; the sink records it. | `pending` |
| [E02](E02-round-trip-log/README.md) | round-trip-log | Same round-trip for a log record. | `pending` |
| [E03](E03-round-trip-metric/README.md) | round-trip-metric | Same round-trip for a metric data point. | `pending` |
| [E04](E04-house-attributes-survive-round-trip/README.md) | house-attributes-survive-round-trip | All four house attributes (`service.name`, `tenant.id`, `feature_flag.*`, `experiment.id`) survive the round-trip on Resource. | `pending` |
| [E05](E05-clean-exit-flushes-last-batch/README.md) | clean-exit-flushes-last-batch | App exiting cleanly drops `SparkGuard`; the last batch reaches Aperture before exit. No silent data loss. | `pending` |
| [E06](E06-sigterm-during-emit-bounded-flush/README.md) | sigterm-during-emit-bounded-flush | App receiving SIGTERM mid-emission triggers bounded flush; tracing surfaces outcome on stderr. | `pending` |

## X — Operations / build / supply chain

| ID | Slug | Behaviour summary | Status |
|---|---|---|---|
| [X01](X01-cargo-test-workspace-green/README.md) | cargo-test-workspace-green | `cargo test --workspace --all-targets --locked` is green on a fresh clone. | `pending` |
| [X02](X02-cargo-deny-green/README.md) | cargo-deny-green | `cargo deny --all-features check` is green (licence + advisory + bans). | `pending` |
| [X03](X03-cargo-public-api-locked/README.md) | cargo-public-api-locked | `cargo public-api` for `otlp-conformance-harness` and `spark` matches the surface locked by ADR-0001 and ADR-0011. | `pending` |
| [X04](X04-cargo-build-release-produces-binary/README.md) | cargo-build-release-produces-binary | `cargo build --workspace --release` produces an executable `aperture` binary. | `pending` |
| [X05](X05-pre-commit-hook-green-on-clean-tree/README.md) | pre-commit-hook-green-on-clean-tree | The pre-commit hook runs the same gates CI runs and exits 0 on a clean workspace. | `pending` |
| [X06](X06-ci-five-gates-green-at-test-sha/README.md) | ci-five-gates-green-at-test-sha | CI on push to main shows the five gates green for the kaleidoscope SHA we test against. | `pending` |
| [X07](X07-license-manifests-correct/README.md) | license-manifests-correct | `otlp-conformance-harness` and `spark` carry `license = "Apache-2.0"`; `aperture` carries `license = "AGPL-3.0-or-later"`. | `pending` |
| [X08](X08-forbid-unsafe-code-in-spark-and-aperture/README.md) | forbid-unsafe-code-in-spark-and-aperture | `forbid(unsafe_code)` is present in `lib.rs` of both `spark` and `aperture`. | `pending` |
