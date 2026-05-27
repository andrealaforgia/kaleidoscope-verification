# Expectations index

## What this catalogue does NOT validate

A satisfied count below is not the same as "the system works".
This catalogue verifies contract-level behavioural correctness
at v0/v1 operator and integrator surfaces. It deliberately does
NOT cover four load-bearing claims a casual reader of the
kaleidoscope README might infer.

- **Architectural thesis** — "OTLP at every internal seam", the
  four-pillar model holding together as a cohesive whole, the
  "removing the vendor margin" framing. We assert wire-shape
  contracts at the boundary, not architectural coherence.
- **Cost thesis** — claims of the form "Aegis is in the free
  product. Always.", "no licence tax", or any total-cost-of-
  ownership argument. The catalogue has no business-economics
  surface.
- **Durability thesis** — "survives a restart" for six storage
  pillars and rule-state. We verify functional ingest + read
  round-trips. We do NOT yet kill-9 mid-write, restart, and
  assert every record landed without corruption. Tracked as a
  follow-up — see [`../known-gaps.md`](../known-gaps.md) N18
  when added.
- **Multi-pillar coherence thesis** — "the platform now runs
  end to end" with all six pillars participating in one flow.
  The current E-prefix tests Spark → aperture → otelcol-sink,
  which is a forwarding path. The gateway→pillars→query-api
  loop is not yet under contract. G-prefix opens this; G01 is
  a smoke contract, not the round-trip.

A green INDEX confirms the contracts that ARE here. The
[`../known-gaps.md`](../known-gaps.md) file enumerates what is
intentionally out of scope (the H-rule excludes library APIs)
and what is deferred pending external anchors or harness work.

Live status table. Updated when an expectation moves between states.

| Status | Count |
|---|---|
| `pending` | 27 (15 in S/E/X + 6 SI blocked on N8 + 6 B blocked on N10) |
| `satisfied` | 64 (A 14 + S 12 + E 4 + X 12 + L 6 + K 11 + Q 2 + G 2 + EG 1) |
| `held` | 1 (K11 — anchored to reverted commit, see [`../known-gaps.md`](../known-gaps.md) N14) |
| `partial` | 0 |
| `broken` | 2 (X01, X05 — [`issue 004`](../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md)) |
| `unanchored-claim` | 0 |
| `out-of-scope` | 6 (H1-H6 — see [`../known-gaps.md`](../known-gaps.md)) |

Last index refresh: 2026-05-27, observed HEAD `cf0ac15` (cycle 30 of overnight loop, kaleidoscope HEAD unchanged from cycle 29). A02, K09, X02 spot re-verified GREEN. No flake this cycle.
60 of 60 re-verified expectations green at HEAD; X01 + X05
remain broken on [issue 004](../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md).
Q01 + G01 + EG01 added at `0c1d66b` — the read-side fails-closed
contract, the gateway startup smoke, and the first true E2E
through the durable pipeline (telemetrygen → gateway → Pulse
→ query-api). Issue 005 opened: query-api and gateway main.rs
emit structured `tracing::error!` events but install no
subscriber, so the documented `health.startup.refused` /
`gateway_starting` events are dropped silently; the runners
assert on the actually-observable signals until the subscribers
land.

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

Open issues:
[004 — cargo test workspace broken (self-observe path-deps)](../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md)
(`open`, reproducing at `4855d69`; affects X01 + X05).
Closed:
[001 — aperture binary ignores --config](../issues/001-aperture-binary-ignores-config-flag.md) (`fixed` at `6b09c0d`);
[002 — env-var overrides not wired](../issues/002-env-var-overrides-not-wired-in-figment-loader.md) (`fixed` at `c8d8a55`);
[003 — gRPC backpressure load reproducibility](../issues/003-grpc-backpressure-load-reproducibility.md) (`wontfix`, catalogue tooling).

## Surfaces overview (catalogue coverage map)

Coverage of every observable surface in kaleidoscope HEAD against
this catalogue. The table below is the answer to "is everything
that can have an expectation, tracked?".

| Kaleidoscope component | Surface | Prefix | Tracked entries | Status |
|---|---|---|---|---|
| `crates/aperture` binary | OTLP gateway runtime (operator) | **A** | 16 (14 satisfied, 2 deferred) | Comprehensive. A07 needs raw gRPC client; A14 needs slow downstream. |
| `crates/spark` library | SDK init + signal emission (integrator), via `harness/spark-consumer` fixture | **S** | 22 (12 satisfied, 10 pending) | Consumer fixture in place; remaining S12-S21 are pattern-repetition extensions. |
| Spark + Aperture round-trip | End-to-end signal flow (operator + integrator) | **E** | 6 (4 satisfied, 2 pending) | E05 implicitly proven by E01-E04 evidence; E06 needs SIGTERM injection on consumer. |
| `crates/otlp-conformance-harness` | Validator library API (library-consumer) | **H** | 6 — all `out-of-scope` | Excluded per the H-rule (library-consumer concern, not operator/integrator-facing). Documented in [`../known-gaps.md`](../known-gaps.md). |
| Workspace / supply chain | cargo test/deny/public-api/build/pre-commit, xtask, Prism build pipeline | **X** | 15 (12 satisfied, 2 broken, 1 deferred) | X01 + X05 broken on issue 004 (`cargo test` self-observe path-deps fail to resolve). X06 (CI gates green) needs authenticated `gh` against the kaleidoscope repo. |
| `crates/sieve` library + SamplingSink decorator | Sampling decisions, observability events | **SI** | 6 placeholders (SI01-SI06, all pending) | Slices 02-06 lock the contracts in `docs/feature/sieve/slices/`; ADR-0021 specifies the decorator wiring. aperture does NOT yet wire sieve at HEAD, and no sieve-consumer harness exists. See `known-gaps.md` N8. |
| `crates/codex` library | Schema lint via SchemaCatalogue | **C** | 0 — no external surface | Codex's only callsite is Spark Slice 07 (`SparkConfig::with_strict_schema_lint`), but Spark's public API does not let the integrator inject unknown resource attributes — every attribute Spark composes is in Codex's blessed set. Lint-failure path is unreachable through the public SDK. Documented in `known-gaps.md` N9. |
| `crates/beacon` library + `crates/beacon-server` binary | Alert rule evaluation + webhook emission (operator) | **B** | 6 placeholders (B01-B06, all pending) | Beacon v0 GRADUATED at `f2c28b5`: real Tokio binary, PromQL HTTP polling, SIGHUP reload, inhibition (Slice 03), multi-sink routing (Slice 04), SLO MWMBR synthesis (Slice 05). B-prefix opened with stubs anchored to the slice docs. Verification blocked on a Beacon harness (mock Prom + wiremock webhook); see `known-gaps.md` N10 — updated. |
| `apps/prism` SPA in a browser | Operator-facing UI (query panel, charts, time-range pickers, auto-refresh) | **P** | 0 — deferred infrastructure | Build pipeline is tracked (X10-X15); the actual UI behaviour would need Playwright-in-container plus a PromQL backend fixture. See `known-gaps.md` N11. |
| `crates/loom` binary | Operator change-control CLI (validate / plan / apply) | **L** | 6 (all satisfied: L01-L06) | Loom v0 graduated at `149e4e4`. Six expectations cover validate exit-code contract (L01-L04), plan determinism (L05), apply idempotency (L06). Verified via `docker run rust:1.88-slim` building loom against the HEAD snapshot and running each scenario with inline TOML fixtures. |
| `crates/aegis` library | JWT validator + tenant catalogue + audit log (consumed by aperture in Phase 2) | none yet | 0 — deferred | Aegis v0 graduated at `fde3cd9` library-only. No binary; intended caller is aperture once TLS/SPIFFE knobs ship (see N1 + N12). Per the H-rule, library API is out of scope until an external consumer exposes it. **The kaleidoscope README markets Aegis as a free product feature; that auth/tenancy claim is unverified at HEAD because no external surface exposes it.** |
| `crates/kaleidoscope-cli` binary | Operator CLI wiring Lumen v1 + Cinder v1 + self-observe (ingest / read / stats / --observe-otlp) | **K** | 12 (11 satisfied: K01-K10 + K12; 1 held: K11) | First runnable product binary, landed at `c96cb18` and extended through `75f15a6` / `946d2c8` / `b503f49` / `9d1f805` / `8ee7091` / `2baa05c` (stats + time-range + Cinder tier dist + Lumen observe + Cinder observe). K12 anchors the cross-writer atomicity wiring at `2baa05c`. K11 (unknown-flag rejection) is `held` because its anchor commit `e7fbee0` was reverted by `e3a8cad`; see N14. Verified via `harness/run-kaleidoscope-cli.sh`. |
| `crates/{lumen,cinder,pulse,ray,strata,augur,sluice}` libraries | Storage / metrics / traces / profiles / cold-tier / AIops / buffer pillars | none direct | 0 — deferred (partial via K-prefix) | Seven new pillar v0 (lumen, sluice, pulse, ray, strata, cinder, augur) and three v1 carry-forwards (lumen, sluice, cinder) landed in this range. All library-only per H-rule. Lumen v1 + Cinder v1 + Pulse-via-self-observe ARE indirectly exercised by K03 + K05 through kaleidoscope-cli. Ray, Strata, Augur, Sluice have no external consumer yet. See `known-gaps.md` N13. |
| `crates/kaleidoscope-gateway` binary | OTLP receiver + storage sink (operator) | **G** | 2 (G01, G02 satisfied) | Multi-stage `Dockerfile.gateway`, ports :4317 + :4318, persists into lumen/ray/pulse. G01 = startup smoke; G02 = fsync probe refuses read-only `/data` (anchored at `5ccf4a9`, ADR-0049 §1). G03+ (OTLP accept per signal, durability mid-write) are the natural next batch. See `known-gaps.md` N16. |
| `crates/query-api` binary | Prometheus `/api/v1/query_range` over Pulse (operator) | **Q** | 2 (Q01, Q02 satisfied) | Multi-stage `Dockerfile.query-api`, port :9090. Q01 = fails closed without tenant; Q02 = honest 400 on oversized window (cap 86400 s, anchored at `b71ad8a`/ADR-0050). Q03+ (result-size cap, label matchers, regex matchers, static-serve, 400-on-bad-promql) are the natural next batch. See `known-gaps.md` N16 + N21. |
| End-to-end via kaleidoscope-gateway | OTLP → pillars → query-api round-trip (operator) | **EG** | 1 (EG01 satisfied) | EG01 verifies the integration thesis under contract for the first time: telemetrygen → gateway :4318 → Pulse store → query-api :9090 → matrix response. EG02-EG05 (gRPC ingest, logs via log-query-api, traces, multi-tenant isolation, durability mid-write) are the natural next batch. See `known-gaps.md` N18 + N19. |
| `crates/log-query-api` binary | `/api/v1/logs` over Lumen (operator) | **LQ** | 0 — deferred (no Dockerfile yet) | Binary builds in-workspace but lacks a packaging Dockerfile at HEAD. See `known-gaps.md` N16. |
| `crates/trace-query-api` binary | `/api/v1/traces` over Ray (operator) | **TQ** (when packaged) | 0 — deferred (no Dockerfile yet) | Graduated to DELIVER at `87d5e6e` (2026-05-26): `crates/trace-query-api/` ships lib + binary serving `GET /api/v1/traces?service=&start=&end=` with the same fails-closed-no-tenant posture as query-api. No packaging Dockerfile at HEAD, same as log-query-api. See `known-gaps.md` N17 (updated). |

The two columns to watch are *Tracked entries* (how the catalogue
sees the surface) and *Status* (why the surface is or is not in
that state). If a surface graduates to runnable, the matching
`known-gaps.md` entry closes and pending placeholders move to
`satisfied`.

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
| [X01](X01-cargo-test-workspace-green/README.md) | cargo-test-workspace-green | `cargo test --workspace --all-targets --locked` green on a fresh clone. | `broken` ([issue 004](../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md)) |
| [X02](X02-cargo-deny-green/README.md) | cargo-deny-green | `cargo deny --all-features check` green. | `satisfied` |
| [X03](X03-cargo-public-api-locked/README.md) | cargo-public-api-locked | Public API matches ADR-0001 / ADR-0011 (tool runs green; diff-vs-baseline form deferred). | `satisfied` |
| [X04](X04-cargo-build-release-produces-binary/README.md) | cargo-build-release-produces-binary | `cargo build --workspace --release` produces an executable `aperture`. | `satisfied` |
| [X05](X05-pre-commit-hook-green-on-clean-tree/README.md) | pre-commit-hook-green-on-clean-tree | `scripts/hooks/pre-commit` green on clean workspace. | `broken` ([issue 004](../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md)) |
| [X06](X06-ci-five-gates-green-at-test-sha/README.md) | ci-five-gates-green-at-test-sha | CI five gates green at the SHA verified. | `pending` (deferred — needs `gh` auth) |
| [X07](X07-license-manifests-correct/README.md) | license-manifests-correct | otlp-conformance-harness/spark = Apache-2.0; aperture = AGPL-3.0-or-later. | `satisfied` |
| [X08](X08-forbid-unsafe-code-in-spark-and-aperture/README.md) | forbid-unsafe-code-in-spark-and-aperture | `forbid(unsafe_code)` in spark and aperture lib.rs. | `satisfied` |
| [X09](X09-xtask-regenerate-codex-corpus-idempotent/README.md) | xtask-regenerate-codex-corpus-idempotent | Running `xtask regenerate-codex-corpus` on a clean tree produces zero diff vs committed corpus (ADR-0023). | `satisfied` |
| [X10](X10-prism-build-produces-dist/README.md) | prism-build-produces-dist | `pnpm -F prism build` produces `apps/prism/dist/` with `index.html` and `assets/`. | `satisfied` |
| [X11](X11-prism-typecheck-green/README.md) | prism-typecheck-green | `pnpm -F prism typecheck` (tsc -b --noEmit) is green. | `satisfied` |
| [X12](X12-prism-vitest-green/README.md) | prism-vitest-green | `pnpm -F prism vitest` (unit tests, jsdom) is green. | `satisfied` |
| [X13](X13-prism-lint-green/README.md) | prism-lint-green | `pnpm -F prism lint` (eslint) is green. | `satisfied` |
| [X14](X14-prism-format-check-green/README.md) | prism-format-check-green | `pnpm -F prism format:check` (prettier --check) is green. | `satisfied` |
| [X15](X15-prism-bundle-size-within-budget/README.md) | prism-bundle-size-within-budget | `pnpm -F prism bundle-size` (gzipped JS bundle ≤ 300 KB) is green. | `satisfied` |

## L — Loom (operator change-control CLI)

| ID | Slug | Behaviour summary | Status |
|---|---|---|---|
| [L01](L01-loom-help-exit-zero/README.md) | loom-help-exit-zero | `loom --help` exits 0 and prints a usage banner with the three subcommands. | `satisfied` |
| [L02](L02-loom-validate-clean-tree-exit-zero/README.md) | loom-validate-clean-tree-exit-zero | `loom validate` on a syntactically valid manifest tree exits 0. | `satisfied` |
| [L03](L03-loom-validate-malformed-toml-exit-non-zero/README.md) | loom-validate-malformed-toml-exit-non-zero | `loom validate` on malformed TOML exits non-zero with a diagnostic. | `satisfied` |
| [L04](L04-loom-validate-unknown-key-exit-non-zero/README.md) | loom-validate-unknown-key-exit-non-zero | `loom validate` rejects unknown TOML keys (no silent acceptance). | `satisfied` |
| [L05](L05-loom-plan-deterministic-byte-output/README.md) | loom-plan-deterministic-byte-output | `loom plan` produces byte-identical output across runs given identical inputs. | `satisfied` |
| [L06](L06-loom-apply-idempotent/README.md) | loom-apply-idempotent | `loom apply` is idempotent: re-applying the same manifest produces no further changes. | `satisfied` |

## K — kaleidoscope-cli (operator product binary)

| ID | Slug | Behaviour summary | Status |
|---|---|---|---|
| [K01](K01-kaleidoscope-cli-help-exit-zero/README.md) | kaleidoscope-cli-help-exit-zero | `kaleidoscope-cli --help` exits 0; usage banner names `ingest` and `read`. | `satisfied` |
| [K02](K02-kaleidoscope-cli-unknown-subcommand-exit-two/README.md) | kaleidoscope-cli-unknown-subcommand-exit-two | Unknown subcommand exits 2 with diagnostic. | `satisfied` |
| [K03](K03-kaleidoscope-cli-ingest-read-roundtrip/README.md) | kaleidoscope-cli-ingest-read-roundtrip | `ingest` then `read` for the same tenant returns the ingested records. | `satisfied` |
| [K04](K04-kaleidoscope-cli-malformed-ndjson-rejected/README.md) | kaleidoscope-cli-malformed-ndjson-rejected | Malformed NDJSON on stdin is rejected with non-zero exit + diagnostic. | `satisfied` |
| [K05](K05-kaleidoscope-cli-observe-otlp-emits-ndjson/README.md) | kaleidoscope-cli-observe-otlp-emits-ndjson | `--observe-otlp <path>` appends OTLP-JSON NDJSON lines. | `satisfied` |
| [K06](K06-kaleidoscope-cli-stats-populated-tenant/README.md) | kaleidoscope-cli-stats-populated-tenant | `stats` emits `records=N` + `earliest=` + `latest=` for a populated tenant. | `satisfied` |
| [K07](K07-kaleidoscope-cli-read-time-range-filter/README.md) | kaleidoscope-cli-read-time-range-filter | `read --since/--until` returns only records in the half-open interval. | `satisfied` |
| [K08](K08-kaleidoscope-cli-stats-time-range-filter/README.md) | kaleidoscope-cli-stats-time-range-filter | `stats --since/--until` reports the same window. | `satisfied` |
| [K09](K09-kaleidoscope-cli-stats-cinder-tier-distribution/README.md) | kaleidoscope-cli-stats-cinder-tier-distribution | `stats` emits a `cinder.hot=N` tier-distribution line. | `satisfied` |
| [K10](K10-kaleidoscope-cli-read-observe-otlp/README.md) | kaleidoscope-cli-read-observe-otlp | `read --observe-otlp` lands `lumen.query.count` in the OTLP-JSON sink. | `satisfied` |
| [K11](K11-kaleidoscope-cli-unknown-flag-rejected/README.md) | kaleidoscope-cli-unknown-flag-rejected | (Anchored on reverted `e7fbee0`; see N14.) | `held` |
| [K12](K12-kaleidoscope-cli-observe-otlp-cinder-wired/README.md) | kaleidoscope-cli-observe-otlp-cinder-wired | `ingest --observe-otlp` lands BOTH `lumen.ingest.count` AND a `cinder.*` metric in the same NDJSON file. | `satisfied` |

## SI — Sieve (sampling decisions, placeholders)

Six pending placeholders (SI01-SI06) anchored to Sieve slice docs; blocked on harness — see [`../known-gaps.md`](../known-gaps.md) N8.

## B — Beacon (alert rule evaluation, placeholders)

Six pending placeholders (B01-B06) anchored to Beacon slice docs; blocked on harness — see [`../known-gaps.md`](../known-gaps.md) N10.
