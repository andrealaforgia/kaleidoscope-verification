# Known gaps

Behaviours that are explicitly NOT expected at the current state of
kaleidoscope. We do not write expectations against these surfaces; doing so
would produce false negatives because the feature is not built yet, or false
positives because the feature exists only as scaffolding.

Source: inter-session feed from the kaleidoscope-developing session,
2026-05-06. Each entry below should be revisited when its referenced phase or
component graduates.

## cinder/sluice swallowed append_wal — code-read finding, NOT black-box reachable

**Noted 2026-06-05 (implementer message 023 + code read).** cinder
`place` (`crates/cinder/src/store.rs:81`) returns `()` — it has NO error
channel — so a WAL append failure is STRUCTURALLY swallowed
(`file_backed.rs:270` `if let Err(_e)`, `:364` `let _ = append_wal(...)`);
sluice does the same. The consequence is the acked-but-not-durable lie: a
placement/enqueue "succeeds" (the operation cannot report failure) while
its WAL write was dropped, so a later read can serve data that never
persisted.

This is real, but NOT black-box reachable from the CLI: inducing a WAL
append failure requires the held writer's `write` to fail AFTER a
successful `open`, within one CLI process. A read-only `/data` or a bad
WAL path fails at OPEN (earlier, like issue 005), not at the append; the
CLI runs as root so file-permission tricks do not bite. The failure is
inducible only via an in-suite failing WAL backend (cf. the fsync
`CountingFsyncBackend` count and power-loss, also not black-box
reachable). So no expectation and no black-box issue is filed.

The implementer is fixing it (give `place` an error channel / surface the
append failure). When it lands, the SURFACED-error behaviour is creditable
to her in-suite failing-backend test; revisit only if a clean black-box
induction (an operator-reachable way to force the WAL write to fail
post-open) becomes available.

## 009-adjacent — ingest re-run of a SUCCESSFUL file doubles (no idempotency key)

**Noted 2026-06-05 (implementer message 023).** issue 009 (non-atomic
ingest) is resolved: a MALFORMED file now commits nothing (K13 GREEN at
`fdfbc28`, all-or-nothing). But a re-run of a SUCCESSFUL, fully-valid
ingest STILL double-commits, because lumen has no idempotency key — the
same file ingested twice lands twice. The implementer scoped this OUT of
009 (it is a larger design concern) and deferred it to a future
`ingest-dedup-v0`. Not pinned: there is no committed dedup contract to
assert, and pinning the double as a defect would pre-empt a design that
has not happened. Revisit when `ingest-dedup-v0` graduates; the
expectation then is "re-running an already-ingested valid file does not
duplicate", scoped to the SUCCESS path (distinct from K13's malformed
path).

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

## N10 — Beacon harness (DONE — built 2026-06-05; B01/B02/B04/B05/B07 green, B03 broken/issue 010, B06 unreachable)

**Updated 2026-05-12 wake-up cycle**: Beacon v0 graduated at
commit `f2c28b5`. The binary is real now: `beacon-server --rules
<DIR> --backend <URL>` loads TOML rules, spawns one Tokio task
per rule, polls the Prometheus HTTP API, drives the pure
transition function, and emits incidents to the configured
sinks. SIGHUP reload + grouping + inhibition (Slice 03), multi-
sink routing (Slice 04), SLO multi-window multi-burn-rate
synthesis (Slice 05) all GREEN.

**RESOLVED (2026-06-05).** The Beacon harness is built:
`harness/Dockerfile.beacon-server` plus a small Python mock that
doubles as the PromQL instant-query backend AND the webhook sink
catcher on a throwaway docker network (a query-aware variant lets X
and Y diverge for inhibition tests). beacon persists rule-state at
`<rules>/.beacon-state`, so the rules dir is mounted writable.

B-prefix outcome on this harness:
- **B01** boots + loads (malformed rule → diagnostic, not fatal); **B02**
  fires + resolves to the webhook; **B04** inhibition storm-collapse
  (Y suppressed while X fires); **B05** multi-sink fan-out; **B07**
  inhibition RELEASE on resolve (Y delivered after X clears). All
  satisfied.
- **B03** (SIGHUP reload) is `broken`, grounding
  [issue 010](issues/010-beacon-sighup-reload-claimed-but-absent.md):
  the docs promise SIGHUP hot-reload but the committed binary installs
  no SIGHUP handler (the handler is in-flight as `beacon-sighup-reload-v0`,
  uncommitted at HEAD `15533b2`). B03 flips GREEN on the DELIVER commit.
- **B06** (SLO MWMBR) stays `pending` — NOT black-box reachable: the SLO
  engine (`synthesise_slo`) is library + in-suite-tests only, not wired
  into beacon-server or the loader (the assessment's "unreachable SLO
  engine"). Buildable once an SLO loading path is wired.

The old "blocked on a harness / deferred to a design conversation"
framing is retired.

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

**K11 RESOLVED (2026-06-01).** The unknown-flag rejection contract
was rebuilt through a clean nWave flow (cli-unknown-flag-rejection-v0)
and re-anchored at `307e447`, which is NOT in the reverted set. K11
moved from `held` to `satisfied`; the rebuild also fixed a real
silent-accept gap (a known subcommand with an unknown flag used to
exit 0). The rest of this note stands as the historical record of the
revert.

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

**Four-quadrants report (2026-06-02) independently confirms and
extends the durability picture** (Q2 findings 1, 2, 5, 6; Q1 on
Pulse). The headline, matching what D01-D04 already scope honestly:

- **fsync gap, four of five stores.** Lumen, Ray, Strata, AND Cinder
  call `wal.flush()` and stop — zero `fsync`/`sync_all`, against 48 in
  Pulse. So an acked write survives a process kill (page cache lives;
  D01/D03 verify this) but NOT a power loss / kernel crash. Only Pulse
  is genuinely crash-durable (`sync_all` per WAL record + snapshot
  fsync + parent-dir fsync, ADR-0049). My D02 README already records
  Pulse's stronger guarantee; D01/D03 record the flush-only limit. The
  report adds Strata + Cinder to the flush-only list.
- **non-atomic snapshot, ALL five stores including Pulse** — see the
  new **[issue 007](issues/007-non-atomic-snapshot-write-can-brick-the-store.md)**:
  `File::create(path)` straight onto the canonical path, no temp+rename,
  so a crash mid-snapshot bricks the store (total loss). Defeats Pulse's
  fsync because the fsynced file is itself torn.
- **Cinder torn-WAL doc-vs-code contradiction** — folded into
  [issue 006](issues/006-torn-wal-tail-blocks-recovery-of-intact-records.md).
- **the test to write is power-loss simulation (kill -9 mid-snapshot,
  reopen)** which the kaleidoscope suite "deliberately does not do" —
  exactly the gap D04 began closing on the WAL side (torn tail) and
  issue 007 names on the snapshot side. Power-loss itself is still not
  black-box reachable in this harness (cannot power-cycle the disk).

**PARTIALLY RESOLVED (2026-06-01).** The **D-prefix** now verifies
the kill-9 durability invariant for the three pillars with a direct
gateway → read-API path: **D01** (Lumen / log via log-query-api),
**D02** (Pulse / metric via query-api), **D03** (Ray / span via
trace-query-api). Each ingests through the gateway, hard-kills the
gateway with SIGKILL (exit 137, confirmed, no graceful flush), then
reopens the store via the read API (WAL replay) and asserts the acked
data is recovered. Per-pillar write-path checked in code first: Lumen
and Ray `flush()` to the kernel before ack (process-kill durable);
Pulse additionally `fsync`s (ADR-0049 §4, power-loss durable too).

Two honest boundaries remain:
1. **Scope is acked-survives-kill, not mid-write tearing.** D01-D03
   kill the gateway AFTER the ack, proving "acked = durable across a
   process kill". They do NOT kill mid-batch to prove the absence of
   torn / half-written records during an in-flight write (step 2's
   "timing-window" variant below). That stronger torn-write invariant
   is still unverified.
2. **Power-loss is not black-box demonstrated** — the harness cannot
   power-cycle the disk; only Pulse's fsync-before-ack mechanism
   (read from code) implies it.

The Cinder / Strata / Sluice / Beacon-RuleState pillars have no
gateway → read-API round-trip path, so the D-prefix shape does not
reach them; they would need bespoke writer+reader fixtures.

Original note:

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

## N19 — E2E through kaleidoscope-gateway (LARGELY RESOLVED — EG01/EG02 + LQ02 + TQ02)

**Updated 2026-06-05.** The gateway loop is now under contract across all
three pillars: **EG01** (OTLP/HTTP metric → gateway → Pulse → query-api
matrix), **EG02** (the OTLP/gRPC counterpart, gateway :4317 → Pulse →
query-api), **LQ02** (OTLP/HTTP log → gateway → Lumen → log-query-api
body_contains round-trip), **TQ02** (span → gateway → Ray →
trace-query-api window+by-id round-trip). Both OTLP transports (HTTP +
gRPC) and all three pillars round-trip end to end. EG03-EG05 (multi-tenant
already covered by LQ07; durability mid-write by the D-prefix) are
optional extensions, not blockers. The original detail below is kept for
the audit trail.

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
  via log-query-api `GET /api/v1/logs`. **DONE (cycle 32):** this
  is exactly what LQ02 verifies (gateway → Lumen → log-query-api
  body_contains round-trip). Filed under the LQ prefix rather than
  EG because the behaviour under test is the log read API's body
  filter, not merely the transport round-trip.
- EG03: OTLP/HTTP metric into gateway lands in Pulse, observable
  via query-api `GET /api/v1/query_range`. (This is what EG01
  already does.)

## N28 — log-query-pagination-v0 graduated (DONE)

**DONE (cycle 33, 2026-05-30).** DELIVER landed mid-cycle:
`5a8b330..4e4060e`, feat `47fc5ef` ("limit and offset pagination
on /api/v1/logs"), design `489f3ed` ("handler-side slice, cap
before slice"), ADR-0057. Contract: `?limit=` (reject
0/negative/non-numeric/over-cap as `invalid limit`; missing = take
all) and `?offset=` (0 valid, no upper cap, past-end yields an
empty page not an error), applied as `skip(offset).take(limit)`
over the stable-ordered post-filter vector AFTER the result-size
cap. **LQ04** verifies all four arms at the running surface
(head page == `full[0:3]`, next page == `full[3:6]` disjoint,
`limit=0` → `400 invalid limit`, offset-past-end → `[]`). GREEN at
first attempt. The cap-before-slice ordering is asserted only
indirectly; a direct test needs a seed exceeding `MAX_RESULT_ROWS`
(left for an LQ-cap expectation alongside #17).

## N27 — EG01 binds bare host ports 4318/9090, flakes under a squatter (DONE)

**DONE (2026-06-01).** EG01's runner now binds the gateway on host
`14323` and query-api on `19097` (unique high ports, the same
convention LQ02-LQ05/TQ01-TQ02 already use), so a parallel
`kaleidoscope-e2e` compose stack squatting `4317-4318`/`9090` no
longer collides with it. Re-verified GREEN at `acca3ec`
(status=success, __name__=gen). The container-internal ports are
unchanged (gateway :4318, query-api :9090); only the host
publish mapping moved.

EG01 (and the original EG driver) publish the gateway on host
`:4317-4318` and query-api on `:9090`. During cycle 32 a parallel
`kaleidoscope-e2e-*` compose stack (the kaleidoscope DEV side's
own end-to-end harness, a different docker-compose project from
this catalogue's `kaleidoscope-expectations`) was left running and
squatting exactly those ports, so any EG run that reused them
would fail at container start with "port is already allocated" —
a harness collision, not a behaviour failure. LQ02 sidesteps it by
binding unique high host ports (`14318`, `19091`) and NOT tearing
down containers the catalogue does not own. EG01 should be
hardened the same way (unique ports, or a pre-flight port-free
check that skips-with-note rather than failing). Until then, an
EG01 red under this exact "port is already allocated" stderr is a
known docked harness flake, not an operator-observable regression;
cross-check by confirming the squatter with `docker ps` before
re-running on free ports.

## N26 — log-body-text-search-v0 in DESIGN/DEVOPS

**RESOLVED (cycle 31, 2026-05-29).** DELIVER landed: `1bfa609`
("feat(log-query-api): body_contains substring filter") and
`6cecd63` ("feat(log-query-api): body_regex regex filter"), with
mutual exclusion at `ca25818` (design). The "blocked on a
project Dockerfile" framing was lazy: log-query-api has a binary
target and an axum listener, so the catalogue stands it up itself
via the catalogue-authored `harness/Dockerfile.log-query-api`.
**LQ01** verifies the body_contains/body_regex mutual-exclusion
400 at the running listener, GREEN at first attempt at `35c314a`.

Original note: commits `29f109b` (discuss) + `de40d49` (design) +
`cf0ac15` (devops) at 2026-05-27. Design Decision: extend
`lumen::Predicate` with `body_contains` substring filter, applied
at query time.

## N25 — query-http-common-v0 graduated

Commits `7f24998` (discuss) + `8adb08a` (design, ADR-0054) +
`a6175f1` (devops, gate-5-mutants CI job) + `51400b1`
(DELIVER, "extract scaffolding from three read APIs") at
2026-05-27. The HTTP-shape seam ADR-0048 deferred has been
lifted: query-api, log-query-api and trace-query-api now
route their parse-tenant + cap-rejection + error-response
shape through the common crate. Pure refactor; the wire
shape stays Prometheus-compatible JSON
`{"status":...,"error":...}`. Q01 and Q02 re-verified GREEN
at `51400b1` (cycle 23), confirming no operator-visible
contract drift on the query-api binary.

## N24 — trace-lookup-by-id-v0 graduated (DONE)

**DONE (2026-05-31).** Verified at the running surface by **TQ01**
at HEAD `a898e757`: `GET /api/v1/traces/by_id` rejects a non-hex
and a wrong-length `trace_id` with `400 "invalid trace_id"` (raw
never echoed), and accepts a valid 32-hex id (`200` on the empty
store). The "blocked by N17" framing is retired: the catalogue now
stands trace-query-api up itself via the catalogue-authored
`harness/Dockerfile.trace-query-api` (same recipe as LQ01), so N17
is no longer a true blocker either. TQ-prefix is open.

Wave shipped DELIVER at `3908240` ("feat(trace-query-api):
`/api/v1/traces/by_id` with 32-hex case-insensitive trace_id",
ADR-0053). `parse_trace_id` rejects empty/missing/wrong-length/
non-hex with a literal 400. The library contract is now real
but `trace-query-api` still lacks a packaging Dockerfile (N17).
As of cycle 31 this is no longer a true blocker: LQ01 proved the
catalogue can author its own runtime Dockerfile for a binary the
project does not package (`harness/Dockerfile.log-query-api`,
modelled on `Dockerfile.query-api`). The same recipe opens
TQ-prefix, given trace-query-api has the same binary-target +
axum-listener shape. The honest remaining work is a
catalogue-authored `Dockerfile.trace-query-api` plus a seeded Ray
store for the by-id lookup round-trip, not the Dockerfile itself.

## N23 — log-query-severity-filter-v0 graduated (DONE)

**DONE (2026-05-31).** Verified at the running surface by **LQ05**
(min_severity round-trip gateway → Lumen → log-query-api at HEAD
`a898e757`): an INFO batch (severity 9) and an ERROR batch
(severity 17) are ingested; `min_severity=WARN` returns only
severity >= 13 (ERROR present, INFO excluded), `min_severity=ERROR`
only >= 17. The "still blocked by N16" framing was retired in cycle
31 when the catalogue began standing log-query-api up itself.

Wave shipped DELIVER at `e281fca` ("feat(log-query-api):
min_severity filter via Predicate::min_severity, before cap").
Contract: `GET /api/v1/logs?min_severity=<level>` filters rows
case-insensitively, BEFORE the result-size cap. The library
contract is now real. **UNBLOCKED (cycle 31):** the catalogue
now stands log-query-api up via the catalogue-authored
`harness/Dockerfile.log-query-api` (the project ships none, but
the binary target + axum listener make a packaging Dockerfile a
catalogue concern, not a blocker). LQ01 is live. The min_severity
filter this note tracks is a clean LQ-prefix candidate now: a
`?min_severity=warn` request returning only the warn+ rows from a
seeded store, alongside the LQ02 body-filter round-trip. Both need
a seeded Lumen store (the same fixture the durability set needs),
which is the remaining work, not the Dockerfile.

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
