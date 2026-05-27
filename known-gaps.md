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

## N14 — Overnight session reverted en bloc (e3a8cad)

Between commits `01dbae0` and `c17f0af` the previous Bea ran an
overnight session that produced 31 direct commits with no nWave
provenance under `docs/feature/`. Andrea reviewed and asked for
the lot to be reverted; `e3a8cad` ("revert: drop overnight
session — methodology violation, not nWave-shaped") returned
the tree state to `01dbae0` byte-for-byte and removed the new
files added during the overnight.

Catalogue impact:

- **K11** (unknown-flag rejection) was anchored on `e7fbee0`,
  one of the dropped commits. Marked `held`; will return to
  `pending` only when the rejection contract is rebuilt through
  a proper nWave flow with a fresh anchoring commit.
- **K01-K10** survive: the post-revert commits `75f15a6`,
  `946d2c8`, `b503f49`, `9d1f805`, `8ee7091`, `2baa05c`
  re-implemented the relevant CLI features through nWave waves
  (each with its own `docs/feature/*` artefacts).
- **K12 candidate**: `2baa05c` ("wire Cinder events into
  --observe-otlp sink") is a distinct operator-facing surface
  that K10 does not exercise. A new K12 would assert that an
  `ingest` invocation also lands `cinder.*` events when paired
  with `--observe-otlp`. Not yet drafted.

Operating rule, going forward: every K-prefix runner should
verify, before promotion, that
`git log e3a8cad..HEAD -- <code path>` shows the anchoring
commit. If the anchor is upstream of `e3a8cad` it might still
exist in HEAD via byte-for-byte reintroduction, but the rule is
cheap to check and catches anchor drift.

## N16 — Three operator binaries graduated; partial coverage at G/Q

Between commits `4855d69` and `0c1d66b` three operator-facing
binaries reached running state (the rest are still libraries
per the H-rule):

- **`crates/kaleidoscope-gateway`** — multi-stage `Dockerfile.gateway`,
  ports :4317 (OTLP/gRPC) + :4318 (OTLP/HTTP/protobuf), persists
  signals to lumen / ray / pulse via `aperture-storage-sink`.
  Catalogue prefix **G**.
- **`crates/query-api`** — multi-stage `Dockerfile.query-api`,
  port :9090, Prometheus-compatible `GET /api/v1/query_range`
  over the Pulse store. Catalogue prefix **Q**.
- **`crates/log-query-api`** — `GET /api/v1/logs` over the Lumen
  store. **No `Dockerfile.log-query-api` at HEAD `0c1d66b`** —
  the binary builds in-workspace but is not yet packaged as a
  runtime image. Catalogue prefix would be **LQ** once a
  Dockerfile lands.

Opened G01 (gateway smoke) and Q01 (query-api fails-closed) as
the cheapest contracts. Round-trip coverage (write via gateway,
read via query-api / log-query-api) is the natural next batch:
gateway slice 01-03 commits persist into lumen/ray/pulse, and
query-api slice 01-04 commits parse PromQL + label matchers
(`=`, `!=`, `=~`, `!~`).

## N18 — Durability claim unverified (kill-9 + restart per v1 pillar)

The kaleidoscope README and ADRs describe the v1 file-backed
stores as "survives a restart". The catalogue currently verifies
functional ingest+read round-trips (K03, K05, K12), which prove
the happy path but NOT the durability invariant under abrupt
process death.

The missing class of expectation: per v1 pillar (lumen, cinder,
pulse, ray, strata, sluice, plus beacon RuleState),

1. Ingest N records through the gateway (or kaleidoscope-cli
   where applicable).
2. SIGKILL the writer process mid-write (timing-window vs
   one-record-at-a-time).
3. Restart the writer.
4. Read back via query-api / kaleidoscope-cli read.
5. Assert every record persisted (no torn/missing/corrupt) OR
   document the exact partial-batch shape the contract permits.

Effort: per-pillar harness extension to inject a kill signal mid-
emit. Pulse + Lumen would be first targets (already exercised
by K-prefix). Sluice / Cinder may need bespoke writer fixtures.

This is the catalogue's biggest credibility lever for v1.

## N19 — E2E through kaleidoscope-gateway unverified

The current E-prefix (E01-E04, E05-E06 pending) exercises
Spark → aperture → otelcol-sink, which is a forwarding path.
The README's "the platform runs end to end" claim is about a
different loop: OTLP in → kaleidoscope-gateway → lumen/ray/pulse
→ query-api / log-query-api → operator-readable output.

That loop is not under contract at HEAD. Open the EG-prefix
(End-to-end via Gateway) with at least three contracts:

- EG01: OTLP/HTTP trace into gateway lands in Ray, observable
  via the trace-query-api when it ships (or via a Ray library
  read in the interim).
- EG02: OTLP/HTTP log into gateway lands in Lumen, observable
  via log-query-api `GET /api/v1/logs`.
- EG03: OTLP/HTTP metric into gateway lands in Pulse, observable
  via query-api `GET /api/v1/query_range`.

EG03 is the lowest-friction first because query-api is the
most-shipped of the three read APIs.

## N25 — query-http-common-v0 in DESIGN

Commits `7f24998` (discuss) + `8adb08a` (design, ADR-0054) +
`a6175f1` (devops, gate-5-mutants CI job) at 2026-05-27
progress the wave. ADR-0054 pins a Mikado-ordered extraction
of the HTTP-shape seam ADR-0048 deferred: the three read APIs (query-api,
log-query-api, trace-query-api) currently re-implement
parse-tenant + cap-rejection + error-response shape; a
common crate is being scoped to lift the seam. No DESIGN
yet. Pure refactor wave: when it lands, no operator-visible
contract changes (the wire shape stays Prometheus-compatible
JSON `{"status":...,"error":...}`), but Q02 and its future
LQ/TQ siblings will exercise the SAME code path. Recheck
Q02 evidence after DELIVER lands.

## N24 — trace-lookup-by-id-v0 graduated, still blocked by N17

Wave shipped DELIVER at `3908240` ("feat(trace-query-api):
`/api/v1/traces/by_id` with 32-hex case-insensitive trace_id",
ADR-0053). `parse_trace_id` rejects empty/missing/wrong-length/
non-hex with a literal 400. The library contract is now real
but `trace-query-api` still lacks a packaging Dockerfile
(N17), so the operator-visible surface remains unreachable
from the catalogue. TQ-prefix opens the moment the Dockerfile
lands.

## N23 — log-query-severity-filter-v0 graduated, still blocked by N16

Wave shipped DELIVER at `e281fca` ("feat(log-query-api):
min_severity filter via Predicate::min_severity, before cap").
Contract: `GET /api/v1/logs?min_severity=<level>` filters rows
case-insensitively, BEFORE the result-size cap. The library
contract is now real but `log-query-api` still lacks a
packaging Dockerfile (N16), so the operator-visible surface
remains unreachable from the catalogue. LQ02 candidate
remains drafabile alongside LQ01 the moment the Dockerfile
lands.

## N22 — pulse-cardinality-watermark-v0 graduated

Wave shipped DELIVER at `936ca75` ("feat(cardinality):
pulse per-tenant cardinality watermark + self-observe bridge",
ADR-0051). `MAX_SERIES_PER_TENANT = 10_000`. Live ingest
refuses series past the cap (partial-apply: WAL records
honour the cap shadow counter under the same Mutex; replay
bypasses enforce_cap so existing state is preserved).
`PulseCardinalityToPulseRecorder` emits
`pulse.series.refused.count` (Sum, tenant as point-level
attribute) via the existing MetricsRecorder hook.

Operator-visible contract through the gateway: ingest a
10_001st distinct series for a tenant, observe a refusal
signal. Two paths exist: (a) `--observe-otlp` on the
kaleidoscope-cli ingest path (Lumen-side; cardinality cap is
Pulse, not Lumen, so not applicable); (b) gateway → Pulse →
query-api for the `pulse.series.refused.count` metric. EG02
candidate (gateway + query-api round-trip on the refusal
metric). Cost: fixture must drive 10_001 distinct label-sets
through the gateway, which is non-trivial.

Deferred until either the fixture lands or a simpler
operator-visible refusal surface ships (e.g. gateway returns
a 429 / structured event on overflow rather than silently
recording it as a self-observe metric).

## N21 — honest-read-caps-v0 graduated

Wave shipped DELIVER at commit `b71ad8a` ("feat(read-caps):
honest 400 for oversized window or result on the three read
APIs"). Cap shape: `MAX_WINDOW_SECONDS = 86400` (24 h),
`MAX_RESULT_ROWS = 100_000`. Refusal path returns 400
`status:error` with the reason naming the cap value verbatim;
the store is never queried.

Q02 anchors the operator-visible window-cap refusal at the
query-api binary. Result-size cap (Q03 candidate) needs a
fixture that loads > 100k rows into Pulse, deferred. The cap
is also implemented in `log-query-api` and `trace-query-api`
libraries, but those still lack packaging Dockerfiles (see
N16 + N17).

## N20 — earned-trust-fsync-probe-v0 graduated

Commits `e409f2d` (design) → `f97b836` (devops) → `5ccf4a9`
(`feat(earned-trust): honour fsync at pulse write path and
gateway startup`) shipped the fsync-honest probe. The gateway
now writes a sentinel, fsyncs, and refuses startup on EROFS
or fsync failure. G02 anchors the operator-visible refusal:
`docker run -v /data:ro` produces `Error: PersistenceFailed
{ reason: "io: Read-only file system (os error 30)" }` and
exits 1. Verified at HEAD `74920c7`.

Residual: the structured `event=health.startup.refused
substrate=<descriptor>` (ADR-0049 §7) is dropped per issue 005.

## N17 — trace-query-api graduated to DELIVER, no Dockerfile yet

ADR-0048 defines the `trace-query-api` crate (Ray read path).
At commit `87d5e6e` (2026-05-26) the crate shipped DELIVER:
`crates/trace-query-api/{lib.rs,main.rs,composition.rs}` exist
with `GET /api/v1/traces?service=&start=&end=` and the same
fail-closed-on-missing-tenant posture as query-api /
log-query-api. Env vars `KALEIDOSCOPE_TRACE_QUERY_TENANT`,
`KALEIDOSCOPE_TRACE_QUERY_ADDR`, `KALEIDOSCOPE_PILLAR_ROOT`.

But `Dockerfile.trace-query-api` does NOT exist at HEAD, same
posture as `log-query-api` (see N16). Without a packaging
Dockerfile no operator-runnable surface exists; per the H-rule
the catalogue defers until either (a) the Dockerfile lands, or
(b) the harness ships its own wrapper. Catalogue prefix would
be **TQ** when adopted, opening with the same fails-closed-no-
tenant smoke and a round-trip in the EG family.

## N15 — cli-migrate-subcommand-v0 in DESIGN wave

`docs/feature/cli-migrate-subcommand-v0/` exists at HEAD with
DISCUSS + DESIGN artefacts (and an untracked `devops/` directory
mid-wave). No `feat(...)` commit has landed yet. The intended
subcommand likely migrates data between Cinder tiers or moves
records between tenants, but the application-architecture.md is
the authoritative source.

No K-prefix entry yet. A K12+ slot opens once the DELIVER wave
ships the binary surface and an `kaleidoscope-cli migrate ...`
invocation produces observable behaviour.
