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

## N10 — Beacon harness not yet built (binary IS runnable now)

**Updated 2026-05-12 wake-up cycle**: Beacon v0 graduated at
commit `f2c28b5`. The binary is real now: `beacon-server --rules
<DIR> --backend <URL>` loads TOML rules, spawns one Tokio task
per rule, polls the Prometheus HTTP API, drives the pure
transition function, and emits incidents to the configured
sinks. SIGHUP reload + grouping + inhibition (Slice 03), multi-
sink routing (Slice 04), SLO multi-window multi-burn-rate
synthesis (Slice 05) all GREEN.

The B-prefix is now opened with six placeholder stubs (B01-B06)
anchored to the slice docs in `docs/feature/beacon-v0/slices/`.
Verification is blocked on the catalogue side: a Beacon harness
similar in shape to `harness/spark-consumer/` is needed, plus a
mock Prometheus HTTP backend (wiremock or a small adapter) and a
wiremock-based webhook sink fixture so the harness can capture
incident deliveries. The harness has not been built.

This is the next natural EDD investment, comparable in scope to
the spark-consumer fixture that unblocked S/E. Deferred to a
session with operator review since the harness layout
(in-container Prom vs sidecar prometheus, webhook fixture, time
travel for the SLO MWMBR alerts) wants a design conversation
first.

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

## N12 — Aegis is library-only at v0 (no external consumer yet)

Aegis v0 graduated at commit `fde3cd9`: JWT validator (HS256, 8
typed ValidationError variants), tenant catalogue (TOML loader,
O(1) contains lookup), audit log via structured tracing events.
All three slices landed in one commit (DESIGN collapsed into
implementation per the Loom precedent). 26 new acceptance tests
GREEN.

Aegis is library-only. There is no `aegis` binary; the only
caller envisioned is aperture once Phase 2 wires TLS/SPIFFE and
the authentication path (see N1 — aperture's
`[aperture.security]` config has the knobs but they are gated
off at v0, with `tls_not_supported_in_v0` event emitted on
opt-in).

Per the H-rule (library-API is out of scope), Aegis carries no
catalogue prefix at HEAD. The natural opening for an A-prefix
extension (or a new AEG-prefix) is when aperture starts honouring
the TLS/SPIFFE knobs in its config schema and the JWT validator
gates incoming OTLP requests. Until then, Aegis's contracts are
exercised internally by `crates/aegis/tests/` only.

## N13 — Seven new pillar libraries (lumen / cinder / pulse / ray / strata / augur / sluice)

Between commits `fde3cd9` and `1df2d59` seven new pillar v0
crates landed (sluice, lumen, pulse, ray, strata, cinder,
augur), plus three v1 carry-forwards (cinder, sluice, lumen).
All library-only at HEAD. Per the H-rule, none carry their own
catalogue prefix.

Three of them — **Lumen v1**, **Cinder v1**, **Pulse via
self-observe** — are indirectly exercised by the K-prefix
expectations because `kaleidoscope-cli` wires them together:

- K03 ingest+read round-trip drives Lumen v1's
  `FileBackedLogStore` and Cinder v1's Hot tier placement.
- K05 `--observe-otlp` exercises the self-observe Lumen→Pulse
  bridge plus the LumenToOtlpJsonWriter cross-process sink.

The remaining four (**Ray**, **Strata**, **Augur**, **Sluice**)
have no external consumer yet. The `integration-suite` crate
runs cross-pillar functional composition tests internally, but
no operator-facing surface exposes those flows. New prefixes
(R, ST, AU, SL or similar) would open when a binary or CLI
exposes them.

Naming convention to follow when those land: use the pillar's
first letter or first two letters when ambiguous (S is taken by
Spark, so Sluice would be SL; Strata would be ST; Sieve already
uses SI). Augur could be AU. Ray is R. Cinder is C (Codex
already uses C — would be CI? CN? Reserve when needed).
