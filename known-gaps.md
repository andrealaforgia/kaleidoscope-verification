# Known gaps

Behaviours that are explicitly NOT expected at the current state of
kaleidoscope. We do not write expectations against these surfaces; doing so
would produce false negatives because the feature is not built yet, or false
positives because the feature exists only as scaffolding.

Source: inter-session feed from the kaleidoscope-developing session,
2026-05-06. Each entry below should be revisited when its referenced phase or
component graduates.

## N1 — TLS / SPIFFE

Knobs exist in aperture's config schema but are off by default at v0.
The schema validator currently rejects `tls.enabled = true`. This belongs
to **Phase 2 / Aegis**.

External anchor: `docs/product/architecture/adr-0008-aperture-configuration-schema.md`,
section "Decision" (TLS/SPIFFE forward-compat knobs, default off).

## N2 — Spark on HTTP/protobuf

Spark v0 uses gRPC by default. HTTP/protobuf transport on the SDK side ships
in **v0.1+**. Until then, S-prefixed expectations assume gRPC.

## N3 — Auto-instrumentation of HTTP / DB clients

Out of scope until **v0.2+**. Spark v0 only auto-instruments what is wired in
the canonical config; HTTP and DB client crates are not yet hooked.

## N4 — Schema validation beyond bytes-conformance

Strict semantic-conventions validation is the domain of **Codex**, a Phase 0+
component that does not yet exist as code. Conformance today is bytes-level
only (`otlp-conformance-harness`).

## N5 — Drained / dropped count integers in shutdown logs

At v0 the shutdown event payload uses the literal string `unknown` for the
counts, e.g. `drained=unknown`, `dropped=unknown`. The contract is the prefix
(`drained=`, `dropped=`), not the value. Real counts arrive in a later slice.
Expectations S16, S17 and A14 assert the prefix only.

## N6 — Persistent buffer for un-flushed records at process exit

A durable on-disk buffer for records that did not flush before exit is the
domain of **Sluice** in Phase 7. Today, un-flushed records are lost; this is
documented behaviour, not a defect.

## N7 — Sieve as downstream sink

`ForwardingSink` today points at "the next stage". In our harness that next
stage is the otelcol file-exporter sidecar, used as a stable, well-known OTLP
receiver. **Sieve**, the sampling/filtering component named in the
architecture, is the eventual consumer but does not yet exist as code.

---

## Rescope: H1-H6 (conformance harness library API)

Items H1-H6 from the inter-session feed cover the public Rust API of
`otlp-conformance-harness` (e.g. `validate_logs`, `Framing` enum,
`OTLP_SPEC_VERSION`). They were proposed but excluded from the initial EDD
catalogue scope.

Reasoning. They are library-consumer expectations, not end-user
(operator/integrator) observable behaviours. Kaleidoscope's own test suite
already covers them as integration tests of the harness crate. EDD value-add
is at the running-system surface, not at the library API surface.

Revisit if and only if `otlp-conformance-harness` is published as a
public Apache-2.0 library that third-party crates embed; at that point
"library consumer" becomes a real external user.

## N8 — Sieve harness not yet wired

Sieve graduated through Slice 06 (rate-zero drop, non-error rate
via xxh3_64, trace-id determinism, logs/metrics passthrough, DEBUG
per-decision events, INFO summary timer, SamplingSink decorator).
The catalogue carries SI01-SI06 as `pending` placeholders anchored
at the slice docs and ADR-0021. Verification is blocked on either
(a) aperture wiring the `SamplingSink` decorator from a future
`aperture.toml` knob, OR (b) a sieve-consumer fixture (similar to
`harness/spark-consumer/`) that links `crates/sieve` and exercises
the decorator in-process. Neither exists at HEAD. Until then the
contracts are exercised internally by `crates/sieve/tests/` only.

## N9 — Codex external surface unreachable

Codex graduated to v0 with Slices 01-05 (canonical pair validation,
semconv 0.27 corpus, house attributes, unknown-attribute lint with
Levenshtein "did you mean" suggestions). The library is consumed
internally by Spark Slice 07 (ADR-0025): with
`SparkConfig::with_strict_schema_lint(true)`, an unknown resource
attribute would cause `spark::init` to return
`Err(SparkError::SchemaValidation(LintReport))`; in default warn
mode it would emit a `tracing::warn!(target = "spark")` event.

But Spark's public API only exposes typed builders for blessed
attributes (`for_service` → `service.name`, `with_tenant_id` →
`tenant.id`, `with_feature_flags` → `feature_flag.*`,
`with_experiment_id` → `experiment.id`), and every one of these
keys is in Codex's blessed set. There is no public API entry
point for an integrator to inject an unknown attribute.

The lint-failure observable contract is therefore unreachable
through Spark's public API at HEAD. The catalogue keeps no
C-prefix entries until either (a) a Spark API extension allows
arbitrary attribute injection, or (b) Codex ships a CLI surface
that operators run directly. Kaleidoscope's own integration tests
under `crates/spark/tests/` and `crates/codex/tests/` cover the
contracts internally.

## N10 — Beacon binary still a placeholder

Beacon graduated through Slice 02 (pure-function rule evaluator,
WebhookSink with retry/permanent classification, TOML rule loader
with Levenshtein-suggestion diagnostics). The library tests pass
under `cargo test`. However, `crates/beacon-server/src/main.rs` at
HEAD is the placeholder shell from ADR-0037 that prints
`"beacon-server placeholder. Implementation arrives at slice 01
DELIVER per ADR-0037."` and exits with code 2.

The B-prefix surface (operator runs beacon-server with a directory
of TOML rules + a PromQL endpoint, the daemon ticks the evaluator,
fires incidents to webhooks, reloads on SIGHUP) is therefore not
externally observable yet. The catalogue keeps no B-prefix entries
until Slice 03 prefix lands the real binary. Slice 02's commit
message explicitly tells us when: "Slice 03 prefix lands the binary
(real Tokio runtime + PromQL HTTP + scheduler + SIGHUP) — moved
out of slice 02 by the SPIKE".

## N11 — Prism UI behaviour needs a Playwright-in-container harness

Prism v0 graduated through Slice 06 (six slices wiring the React
SPA + ECharts + PromQL backend client + reducers). The build
pipeline is tracked by X10-X15. The operator-facing UI behaviour —
loading the SPA, submitting a query, panning the chart, picking a
time range, auto-refresh ticking, postmortem permalink, WCAG 2.2
AA pass — is **not** in the catalogue.

The Playwright e2e suite under `apps/prism/e2e/` exercises these
contracts internally; an external EDD harness would need
Playwright-in-container plus a Prometheus or Mimir fixture for
the backend. That's a substantial new harness component — similar
in size to the spark-consumer fixture but with browser machinery.
The catalogue keeps no P-prefix entries until that infrastructure
lands. P01-P06 would naturally mirror the six Prism slices.
