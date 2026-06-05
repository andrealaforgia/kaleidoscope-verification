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
| `pending` | 22 (15 in S/E/X + 6 SI blocked on N8 + 1 B — B06; B01/B02/B04/B05 satisfied, B03 broken) |
| `satisfied` | 110 (A 15 + S 12 + E 4 + X 14 + L 6 + K 13 + Q 6 + G 3 + EG 1 + LQ 7 + TQ 4 + D 20 + B 5) |
| `held` | 0 (K11 came off held 2026-06-01 — re-anchored at `307e447` via cli-unknown-flag-rejection-v0, see [`../known-gaps.md`](../known-gaps.md) N14) |
| `partial` | 0 |
| `broken` | 1 (**B03** — RED grounding [`issue 010`](../issues/010-beacon-sighup-reload-claimed-but-absent.md): docs promise SIGHUP rule hot-reload but beacon-server installs no SIGHUP handler, so SIGHUP is a silent no-op; flips GREEN if a reload handler lands. A17 flipped GREEN 2026-06-05 — `tls-config-reject-v0` resolved [`issue 008`](../issues/008-tls-enabled-claims-rejection-but-binds-plaintext.md). X01/X05 recovered 2026-05-31 — [`issue 004`](../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md) was a harness OOM artefact) |
| `unanchored-claim` | 0 |
| `out-of-scope` | 6 (H1-H6 — see [`../known-gaps.md`](../known-gaps.md)) |

Last index refresh: 2026-06-02, observed HEAD `b286cb4` (verifier+channel loop tick). **issue 005 fully RESOLVED**: gateway-tracing-subscriber-v0 landed (feat `caa8cdf`) — the gateway now installs a JSON tracing subscriber EARLY in main, fixing the ordering gap (gateway_starting was emitted before aperture installed its subscriber and was dropped). **G01 tightened** from aperture's `event=ready` onto the gateway's OWN structured `gateway_starting`→`listener_bound` (asserting both are JSON INFO and the order), and hardened to a unique high host port (`14329`, N27 — it was still on bare `4318` and collided with the dev-side e2e squatter). All four binaries now observable; issue 005 closed (the gateway fsync-probe `health.startup.refused` arm is covered by the implementer's acceptance test, not black-box reachable since a read-only `/data` fails earlier at store-open).

Prior refresh (HEAD `2bab0b6`): **K11 came off `held`**: cli-unknown-flag-rejection-v0 landed (feat `307e447`) and re-anchored the unknown-flag rejection contract through a clean nWave flow — and fixed a real silent-accept gap (a known subcommand with an unknown flag, e.g. `read ... --bogus`, used to exit 0). Re-verified GREEN at `2bab0b6` (top-level/bad-subcommand/subcommand-unknown-flag all exit 2 + usage; a known flag is parsed); the anchor check confirms `307e447` is reachable and not reverted. held 1→0. Implementer also accepted issue 006 (option 1: torn-tail truncation, queued as wal-torn-tail-recovery-v0) and queued gateway-tracing-subscriber-v0 (to take issue 005 partial→resolved).

Prior refresh (HEAD `eef7576`): Across a quiet kaleidoscope window (K11 rebuild moving DISCUSS→DESIGN→DEVOPS, no DELIVER; gateway subscriber queued) the idle-tick backlog built the **durability set** (#17): **D01** (Lumen log), **D02** (Pulse metric), **D03** (Ray span) each prove an acked datum survives a gateway SIGKILL (exit 137) and is recovered from the pillar WAL on reopen — per-pillar fsync/flush contract read from code first (Lumen+Ray flush-to-kernel = process-kill durable; Pulse fsyncs = power-loss durable too, though only kill-9 is demonstrated). **D04** is the deterministic torn-write complement: a torn trailing WAL line makes Lumen fail closed with a clear `PersistenceFailed` and serve NO corrupt data (SAFE, GREEN) — but also blocks recovery of the intact prior records, filed as [issue 006](../issues/006-torn-wal-tail-blocks-recovery-of-intact-records.md). **LQ06/TQ04** added the read-tier fails-closed structured-event assertions (issue 005 read part resolved, `partial` on the gateway). **LQ07** pins cross-tenant read isolation. **N27** retired (EG01 ports hardened). N18 PARTIALLY resolved — power-loss and live-process mid-write tearing remain honestly open.

Prior refresh (HEAD `2663eb5`): **read-api-tracing-subscriber-v0** landed (feat `2663eb5`): a shared `query_http_common::init_tracing` installs a JSON-to-stderr tracing subscriber in all three read binaries, so the fail-closed arm now emits a structured `health.startup.refused` (ERROR) event. **Q01 tightened** from the bare `Err()` text onto a `jq`-parsed structured-event assertion; **LQ06 and TQ04 added** (log/trace fails-closed, asserting the same). [issue 005](../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md) moved to `partial`: read tier RESOLVED, but `kaleidoscope-gateway` still has no subscriber (G01 unchanged) — flagged to the implementer as a follow-up. The empty-container-stderr notes on LQ01/LQ02/LQ03/TQ01 are retired.

Prior refresh (HEAD `eed810d`/`2e8bc8b`): **perf-kpi-ci-gating-v0** landed (feat `eed810d`, ADR-0058): the 28 wall-clock p95 KPI tests now early-return unless `KALEIDOSCOPE_PERF_TESTS` is set. X01 and X05 re-verified GREEN with that gate active — both runners deliberately leave the var unset, so those tests skip deterministically (CI enforces them; a Docker VM under variable host load cannot give a stable timing environment). No observable runtime behaviour landed (the feature is test-files + ci.yml only). New surface coverage this session: **TQ01** opened the trace-query-api surface (by-id rejects malformed `trace_id` with `400 invalid trace_id`; ADR-0053). All three read APIs (query-api, log-query-api, trace-query-api) are now covered.

Prior refresh (2026-05-31, HEAD `bbded968`): **X01 and X05 recovered**: issue 004 (the workspace `cargo test` "broken" since 2026-05-19) was MISATTRIBUTED to kaleidoscope. It is a harness OOM under Docker Desktop's ~2-4 GB VM cap (parallel `--all-targets` codegen kills rustc and leaves partial rlibs → spurious E0463 "can't find crate"). Cross-confirmed by Bea Implementer's clean 7.18s `self-observe` build and a local `-j1` full-workspace GREEN diagnostic; fixed by `CARGO_BUILD_JOBS=1` in both runners. Both now GREEN at `bbded968`. Broken count 2→0. Second, a comms channel with Bea Implementer is live in `~/dev/kaleidoscope-agents-shared` (defects reported, triaged: issue 005 subscriber → her nWave queue; K11 anchor → her nWave queue). Kaleidoscope HEAD advanced `4e4060e..bbded968` but only perf-kpi-ci-gating-v0 DISCUSS/DESIGN/DEVOPS (CI/doc only), no observable behaviour.

Prior refresh (cycle 33, HEAD `4e4060e`): landed **log-query-pagination-v0** (feat `47fc5ef`, ADR-0057). Three new LQ expectations GREEN at the clean `4e4060e`: **LQ03** (body_regex round-trip, regex semantics proven by `ig{2}u` matching vs the stricter `ig{3}u` returning `[]`), **LQ04** (pagination: `limit=3`==`full[0:3]`, `offset=3&limit=3`==`full[3:6]` disjoint, `limit=0`→`400 invalid limit`, offset-past-end→`[]`).

Prior refresh (cycle 32, HEAD `5a8b330`): **LQ02** proved the log `body_contains` filter actually FILTERS across the durable boundary. `harness/run-eg.sh` extended to build log-query-api too.

Prior refresh (cycle 31, HEAD `35c314a`): **LQ01** opened the log-query-api surface (`body_contains`/`body_regex` mutual-exclusion 400). The catalogue now builds log-query-api itself (catalogue-authored `harness/Dockerfile.log-query-api`), retiring the lazy "blocked on a project Dockerfile" framing in N23/N26.
X01 + X05 recovered 2026-05-31 ([issue 004](../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md)
was a harness OOM artefact, now `resolved`).
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
[007 — non-atomic snapshot write bricks the store](../issues/007-non-atomic-snapshot-write-can-brick-the-store.md)
(`open`; from the four-quadrants report — `File::create(path)` with no temp+rename in all five stores, so a crash mid-snapshot = total loss; not yet black-box reachable (snapshot not auto-triggered); flagged to the implementer).
[008 — `tls.enabled=true` claims rejection but binds plaintext](../issues/008-tls-enabled-claims-rejection-but-binds-plaintext.md)
(`resolved` 2026-06-05; `tls-config-reject-v0` / ADR-0061 feat `a56c317` deleted the warn-and-bind path — aperture now REFUSES to start on `tls.enabled=true` with `event=config_validation_failed` + exit 2 + no listener, black-box verified by **A17** at `a812193`).
[009 — CLI ingest non-atomic (partial commit + double-ingest)](../issues/009-cli-ingest-non-atomic-partial-commit-double-ingest.md)
(`open`, data integrity; black-box verified by K13 — a malformed mid-stream line aborts non-zero but leaves the flushed batch committed, and a re-run double-ingests; from the four-quadrants per-module report).
[010 — beacon SIGHUP rule reload documented but absent](../issues/010-beacon-sighup-reload-claimed-but-absent.md)
(`open`, operational; black-box grounded by B03 — docs (c4/slice-02/wave-decisions) promise SIGHUP hot-reload but beacon-server installs no SIGHUP handler, so editing rules + SIGHUP is a silent no-op (process keeps the old catalogue, no reload, no error); the implementer's call to implement the handler or correct the docs).
Closed:
[001 — aperture binary ignores --config](../issues/001-aperture-binary-ignores-config-flag.md) (`fixed` at `6b09c0d`);
[002 — env-var overrides not wired](../issues/002-env-var-overrides-not-wired-in-figment-loader.md) (`fixed` at `c8d8a55`);
[003 — gRPC backpressure load reproducibility](../issues/003-grpc-backpressure-load-reproducibility.md) (`wontfix`, catalogue tooling);
[004 — cargo test workspace broken](../issues/004-cargo-test-workspace-broken-self-observe-path-deps.md) (`resolved` 2026-05-31, harness OOM artefact not a kaleidoscope defect; fixed by `CARGO_BUILD_JOBS=1`);
[006 — torn WAL tail](../issues/006-torn-wal-tail-blocks-recovery-of-intact-records.md) (`resolved` 2026-06-04; all four pillars black-box verified recovering the intact prefix past a torn tail on the shared wal_recovery seam — lumen D04, ray D05, pulse D06, cinder D07 (via CLI). cinder DID brick before its fix; the over-retraction was corrected on the implementer's timestamped evidence + D07);
[005 — read/gateway tracing subscriber](../issues/005-query-api-tracing-subscriber-missing-health-events-dropped.md) (`resolved` 2026-06-02; all four binaries install a subscriber — read tier at `2663eb5` (Q01/LQ06/TQ04), gateway at `caa8cdf` (G01 tightened onto gateway_starting→listener_bound ordering); the gateway fsync-probe `health.startup.refused` arm is covered by the implementer's acceptance test, not black-box reachable here).

## Surfaces overview (catalogue coverage map)

Coverage of every observable surface in kaleidoscope HEAD against
this catalogue. The table below is the answer to "is everything
that can have an expectation, tracked?".

| Kaleidoscope component | Surface | Prefix | Tracked entries | Status |
|---|---|---|---|---|
| `crates/aperture` binary | OTLP gateway runtime (operator) | **A** | 17 (15 satisfied, 2 deferred) | Comprehensive. A07 needs raw gRPC client; A14 needs slow downstream. A17 = refuses to start on `tls.enabled=true` (`event=config_validation_failed`, exit 2, no bind; resolves issue 008). |
| `crates/spark` library | SDK init + signal emission (integrator), via `harness/spark-consumer` fixture | **S** | 22 (12 satisfied, 10 pending) | Consumer fixture in place; remaining S12-S21 are pattern-repetition extensions. |
| Spark + Aperture round-trip | End-to-end signal flow (operator + integrator) | **E** | 6 (4 satisfied, 2 pending) | E05 implicitly proven by E01-E04 evidence; E06 needs SIGTERM injection on consumer. |
| `crates/otlp-conformance-harness` | Validator library API (library-consumer) | **H** | 6 — all `out-of-scope` | Excluded per the H-rule (library-consumer concern, not operator/integrator-facing). Documented in [`../known-gaps.md`](../known-gaps.md). |
| Workspace / supply chain | cargo test/deny/public-api/build/pre-commit, xtask, Prism build pipeline | **X** | 15 (14 satisfied, 0 broken, 1 deferred) | X01 + X05 recovered 2026-05-31: issue 004 was a harness OOM under the ~2-4 GB Docker VM cap (parallel `--all-targets` codegen left partial rlibs → spurious E0463), fixed by `CARGO_BUILD_JOBS=1` in both runners. X06 (CI gates green) needs authenticated `gh` against the kaleidoscope repo. |
| `crates/sieve` library + SamplingSink decorator | Sampling decisions, observability events | **SI** | 6 placeholders (SI01-SI06, all pending) | Slices 02-06 lock the contracts in `docs/feature/sieve/slices/`; ADR-0021 specifies the decorator wiring. aperture does NOT yet wire sieve at HEAD, and no sieve-consumer harness exists. See `known-gaps.md` N8. |
| `crates/codex` library | Schema lint via SchemaCatalogue | **C** | 0 — no external surface | Codex's only callsite is Spark Slice 07 (`SparkConfig::with_strict_schema_lint`), but Spark's public API does not let the integrator inject unknown resource attributes — every attribute Spark composes is in Codex's blessed set. Lint-failure path is unreachable through the public SDK. Documented in `known-gaps.md` N9. |
| `crates/beacon` library + `crates/beacon-server` binary | Alert rule evaluation + webhook emission (operator) | **B** | 7 (B01/B02/B04/B05/B07 satisfied; B03 broken/issue 010; B06 pending — SLO engine NOT black-box reachable, the assessment's "unreachable SLO engine"). B07 = inhibition RELEASE (X resolves → Y's suppressed Firing delivered, deferred-not-lost), completing B04's suppression. Harness: `harness/Dockerfile.beacon-server` + a mock that doubles as instant-query backend and webhook catcher (query-aware variant for B04/B07). | Beacon v0 GRADUATED at `f2c28b5`: real Tokio binary, PromQL HTTP polling, SIGHUP reload, inhibition (Slice 03), multi-sink routing (Slice 04), SLO MWMBR synthesis (Slice 05). **B02** is the first black-box: beacon-server polls a mock instant-query backend that goes Active then Inactive, and POSTs a Firing then a Resolved Incident to its webhook sink (captured, asserted). This BUILDS the reusable beacon harness (`harness/Dockerfile.beacon-server` + a mock that doubles as backend and webhook catcher on a throwaway docker network); N10 was the blocker and is now lifted. B01 (boots+loads), B03 (SIGHUP reload), B04 (inhibition), B05 (multi-sink), B06 (SLO MWMBR) reuse it. Note: query-api serves only `/api/v1/query_range`, not the instant `/api/v1/query` beacon polls, so a mock backend drives beacon (it is backend-agnostic by design). |
| `apps/prism` SPA in a browser | Operator-facing UI (query panel, charts, time-range pickers, auto-refresh) | **P** | 0 — deferred infrastructure | Build pipeline is tracked (X10-X15); the actual UI behaviour would need Playwright-in-container plus a PromQL backend fixture. See `known-gaps.md` N11. |
| `crates/loom` binary | Operator change-control CLI (validate / plan / apply) | **L** | 6 (all satisfied: L01-L06) | Loom v0 graduated at `149e4e4`. Six expectations cover validate exit-code contract (L01-L04), plan determinism (L05), apply idempotency (L06). Verified via `docker run rust:1.88-slim` building loom against the HEAD snapshot and running each scenario with inline TOML fixtures. |
| `crates/aegis` library | JWT validator + tenant catalogue + audit log (consumed by aperture in Phase 2) | none yet | 0 — deferred | Aegis v0 graduated at `fde3cd9` library-only. No binary; intended caller is aperture once TLS/SPIFFE knobs ship (see N1 + N12). Per the H-rule, library API is out of scope until an external consumer exposes it. **The kaleidoscope README markets Aegis as a free product feature; that auth/tenancy claim is unverified at HEAD because no external surface exposes it.** |
| `crates/kaleidoscope-cli` binary | Operator CLI wiring Lumen v1 + Cinder v1 + self-observe (ingest / read / stats / --observe-otlp) | **K** | 12 (all satisfied: K01-K12) | First runnable product binary, landed at `c96cb18` and extended through `75f15a6` / `946d2c8` / `b503f49` / `9d1f805` / `8ee7091` / `2baa05c`. K12 anchors the cross-writer atomicity wiring at `2baa05c`. K11 (unknown-flag rejection) came off `held` on 2026-06-01: re-anchored at `307e447` (cli-unknown-flag-rejection-v0) after the original `e7fbee0` was reverted (N14) — the fix also closed a real silent-accept gap (a known subcommand with an unknown flag used to exit 0). Verified via `harness/run-kaleidoscope-cli.sh` with the anchor check. |
| `crates/{lumen,cinder,pulse,ray,strata,augur,sluice}` libraries | Storage / metrics / traces / profiles / cold-tier / AIops / buffer pillars | none direct | 0 — deferred (partial via K-prefix) | Seven new pillar v0 (lumen, sluice, pulse, ray, strata, cinder, augur) and three v1 carry-forwards (lumen, sluice, cinder) landed in this range. All library-only per H-rule. Lumen v1 + Cinder v1 + Pulse-via-self-observe ARE indirectly exercised by K03 + K05 through kaleidoscope-cli. Ray, Strata, Augur, Sluice have no external consumer yet. See `known-gaps.md` N13. |
| `crates/kaleidoscope-gateway` binary | OTLP receiver + storage sink (operator) | **G** | 3 (G01-G03 satisfied) | Multi-stage `Dockerfile.gateway`, ports :4317 + :4318, persists into lumen/ray/pulse. G01 = structured startup lifecycle (gateway_starting→listener_bound, after the subscriber landed at `caa8cdf`); G02 = fsync probe refuses read-only `/data` (ADR-0049 §1); G03 = strict OTLP/HTTP content-type gating (json/lookalike → 415, no lax `starts_with`; from the four-quadrants report Q1). Durability mid-write is the D-prefix. See `known-gaps.md` N16. |
| `crates/query-api` binary | Prometheus `/api/v1/query_range` over Pulse (operator) | **Q** | 3 (Q01, Q02, Q03 satisfied) | Multi-stage `Dockerfile.query-api`, port :9090. Q01 = fails closed without tenant; Q02 = honest 400 on oversized window (cap 86400 s, anchored at `b71ad8a`/ADR-0050); Q03 = `step` is accepted and IGNORED at v0 (DD5: raw points, no re-stepping) — two query_range calls over one window differing only in step return byte-identical `.data.result`; disclosed v0 contract, GREEN regression guard, not an issue. Q04 = malformed PromQL (empty / unterminated brace / unrecognised syntax) → honest 400 `status:error` and NO echo of the raw query (ZZLEAKZZ canary absent). Q05 = invalid `=~` regex matcher → 400 `status:error` naming the matcher invalid, NO echo of the pattern. Q06 = label matchers are HONOURED — `gen{__name__="gen"}` returns the series, `gen{__name__="<no>"}` returns empty (the matcher changes the result, the deliberate contrast to Q03's ignored step). The result-size cap (`MAX_RESULT_ROWS=100_000`) is NOT black-box reachable (needs >100k distinct series ingested) — left to in-suite tests, see `known-gaps.md`. See `known-gaps.md` N16 + N21. |
| End-to-end via kaleidoscope-gateway | OTLP → pillars → query-api round-trip (operator) | **EG** | 1 (EG01 satisfied) | EG01 verifies the integration thesis under contract for the first time: telemetrygen → gateway :4318 → Pulse store → query-api :9090 → matrix response. EG02-EG05 (gRPC ingest, logs via log-query-api, traces, multi-tenant isolation, durability mid-write) are the natural next batch. See `known-gaps.md` N18 + N19. |
| `crates/log-query-api` binary | `/api/v1/logs` over Lumen (operator) | **LQ** | 7 (LQ01-LQ07 satisfied) | log-query-api has a binary target + axum listener at HEAD (`crates/log-query-api/src/main.rs`). The project ships no Dockerfile, so the catalogue authors its own (`harness/Dockerfile.log-query-api`) and stands the binary up. LQ01 = `body_contains`/`body_regex` mutual-exclusion 400 (ADR-0056 DD4). LQ02 = body_contains round-trip gateway → Lumen → log-query-api (ADR-0055, feat `1bfa609`). LQ03 = body_regex round-trip with regex semantics proven (ADR-0056, feat `6cecd63`). LQ04 = `limit`/`offset` pagination with cap-then-slice + the `invalid limit` 400 (ADR-0057, feat `47fc5ef`). LQ05 = `min_severity` floor filters across the durable boundary (ADR-0052, feat `e281fca`; closes N23). LQ06 = fails-closed-no-tenant asserting the structured `health.startup.refused` event (after the subscriber landed at `2663eb5`). LQ07 = cross-tenant read isolation (logs ingested under tenant-a are invisible to tenant-b, while tenant-a reads them — isolation not absence). An LQ result-cap (>`MAX_RESULT_ROWS`) is the remaining candidate. See `known-gaps.md` N16. |
| `crates/trace-query-api` binary | `/api/v1/traces` + `/api/v1/traces/by_id` over Ray (operator) | **TQ** | 4 (TQ01-TQ04 satisfied) | trace-query-api has a binary target + axum listener on :9092 (`crates/trace-query-api/src/main.rs`), env `KALEIDOSCOPE_TRACE_QUERY_TENANT`, store at `pillar_root/ray`. The project ships no Dockerfile, so the catalogue authors its own (`harness/Dockerfile.trace-query-api`, same recipe as LQ01) and stands the binary up. TQ01 = by-id rejects malformed `trace_id` with `400 "invalid trace_id"` (raw never echoed), valid 32-hex accepted (ADR-0053 DD2, feat `3908240`). TQ02 = traces round-trip on BOTH arms (window `?service=&start=&end=` returns ingested spans filtered by service, bogus service → `[]`; a `trace_id` discovered from the window response resolves via by-id to its spans). TQ03 = window-arm parse guards (missing `service` → `400 "invalid request: service is required"`, window >86400s → `400 "window exceeds 86400 seconds"`, valid → 200). TQ04 = fails-closed-no-tenant, asserting the structured `health.startup.refused` JSON event (after the subscriber landed at `2663eb5`). Opened N17/N24. |
| Durability (kill-9-mid-write per pillar) | acked data survives a hard process kill (operator) | **D** | 20 (D01-D20 satisfied) | D01 (Lumen/log), D02 (Pulse/metric), D03 (Ray/span): an acked datum survives a gateway SIGKILL (exit 137, no graceful flush) and is recovered from the pillar's WAL on reopen, readable via the matching read API. Scoped to PROCESS-kill durability (OS page cache survives). Per-pillar fsync contract verified in code first: Lumen + Ray `flush()` to the kernel before ack (process-kill durable); Pulse additionally `fsync`s (`sync_all`, ADR-0049 §4) before ack (power-loss durable too, though only kill-9 is black-box demonstrated). The three pillars with a direct gateway→read-API path are now complete; Cinder/Strata/Sluice/Beacon RuleState have no such round-trip path. D04 = the deterministic torn-write complement (Lumen): a torn WAL trailing line makes the store fail closed with a clear `PersistenceFailed: WAL parse error` and serve NO corrupt data (SAFE invariant, GREEN) — but it also blocks recovery of the intact prior records, filed as [issue 006](../issues/006-torn-wal-tail-blocks-recovery-of-intact-records.md). **D04-D07** then close issue 006 across all four WAL pillars (lumen/ray/pulse/cinder recover the intact prefix past a torn tail). **D08/D09** black-box the two halves of store-fsync-durability-v0 the implementer cannot prove by process kill (the page cache hides flush-vs-fsync): **D08** = WAL-fsync REFUSAL — `lumen-crash-target --probe-lying` drives the composition root against a lying fsync substrate and refuses to open (`event=health.startup.refused substrate=fsync-noop`, non-zero exit, no payload written); **D09** = SNAPSHOT ATOMICITY — `--seed-then-loop-snapshot` SIGKILLed mid-loop leaves the canonical `store.snapshot` whole-or-absent (never torn) with the acked datum durable. The fsync-IS-called happy-path count stays in-suite (CountingFsyncBackend, not black-box reachable) and is credited to the implementer. Both via `harness/run-crash-target.sh` + `Dockerfile.crash-target`. **D10-D14** then extend the WAL-fsync REFUSAL proof to every other store that ships the probe — ray (D10), strata (D11), cinder (D12), sluice (D13), beacon (D14) — each `--probe-lying` refusing a lying substrate (`event=health.startup.refused substrate=fsync-noop`, non-zero exit, no payload), via the shared `harness/assert-probe-lying-refusal.sh`. Pulse ships only the snapshot mode (it historically fsynced) so has no probe-lying instance. **D15-D20** then complete the SNAPSHOT-ATOMICITY axis across every store — ray (D15), pulse (D16), strata (D17), cinder (D18), sluice (D19), beacon (D20) — each `--seed-then-loop-snapshot` SIGKILLed mid-loop leaving the canonical `store.snapshot` whole-or-absent (never torn) with the seeded acked datum durable; several froze a `.tmp` in flight while the canonical stayed whole. With D09 lumen that is all seven stores, via the shared `harness/assert-snapshot-atomicity.sh`. This grounds [`issue 007`](../issues/007-non-atomic-snapshot-write-can-brick-the-store.md) black-box (now `resolved`: snapshot writes go through `wal_recovery::atomic_write_snapshot`). The fsync-IS-called happy-path count stays in-suite (CountingFsyncBackend), credited to the implementer. See `known-gaps.md` #17 / N18. |

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
| [A17](A17-aperture-tls-enabled-refuses-to-start/README.md) | aperture-tls-enabled-refuses-to-start | `tls.enabled=true` makes aperture REFUSE to start (`event=config_validation_failed` naming the knob, exit 2, no listener bound). Resolves issue 008; was the first `broken` (RED grounding) then flipped GREEN on `tls-config-reject-v0` (`a56c317`). | `satisfied` |

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
| [K11](K11-kaleidoscope-cli-unknown-flag-rejected/README.md) | kaleidoscope-cli-unknown-flag-rejected | An unknown flag (top-level, bad subcommand, OR a known subcommand with an unknown flag) is a usage error: exit 2 + usage block on stderr; a known flag is parsed. Re-anchored at `307e447`. | `satisfied` |
| [K12](K12-kaleidoscope-cli-observe-otlp-cinder-wired/README.md) | kaleidoscope-cli-observe-otlp-cinder-wired | `ingest --observe-otlp` lands BOTH `lumen.ingest.count` AND a `cinder.*` metric in the same NDJSON file. | `satisfied` |

## SI — Sieve (sampling decisions, placeholders)

Six pending placeholders (SI01-SI06) anchored to Sieve slice docs; blocked on harness — see [`../known-gaps.md`](../known-gaps.md) N8.

## B — Beacon (alert rule evaluation, placeholders)

Six pending placeholders (B01-B06) anchored to Beacon slice docs; blocked on harness — see [`../known-gaps.md`](../known-gaps.md) N10.
