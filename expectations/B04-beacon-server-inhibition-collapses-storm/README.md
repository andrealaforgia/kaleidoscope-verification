# B04 — beacon-server-inhibition-collapses-storm

## Surface

Beacon (`beacon-server`), cross-rule inhibition (ADR-0035, KPI3
storm-collapse). Operator-facing. Reuses the B02 Beacon harness.

## Behaviour

Given two rules both Active, where X declares `inhibits = ["Y"]`, and X is
Firing
When Y also reaches Firing
Then Y's Firing is SUPPRESSED — held pending, not delivered to Y's sinks —
while X's Firing is delivered normally. Y resumes only once X resolves.

## How the test is made deterministic

The shared `InhibitionResolver` suppresses Y only if X is already Firing
when Y's Firing arrives, so the test must order them. X has
`for_duration=0s` (fires on the first Active tick, ~1s); Y has
`for_duration=4s` (reaches Firing ~5s, after X). The mock keeps both
queries Active throughout (`FIRING_WINDOW=100`), so X never resolves and
Y stays suppressed. `RUST_LOG=debug` captures Y's internal state
transition to Firing, so Y's absence at the sink is proven to be
SUPPRESSION, not "Y never fired" — the load-bearing distinction.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`894cc51`). GREEN. At the webhook
  sink: only `{"name":"b04-x-inhibitor","resolved_at":null}` — X delivered,
  Y absent. In beacon's debug log, Y is observed transitioning
  `Inactive → Pending → Firing` (the Pending→Firing step 4s after Pending,
  i.e. while X was already Firing), confirming Y reached Firing and was
  then suppressed.
- Method: self-contained (`.no-compose`). beacon-server + a mock that
  doubles as Active backend and webhook catcher on a throwaway docker
  network; asserts X present at the sink, Y reached Firing internally, Y
  absent from the sink.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `894cc51`.
- [`evidence/incidents.ndjson`](evidence/incidents.ndjson) — only X's
  incident.
- [`evidence/beacon-server.stderr.txt`](evidence/beacon-server.stderr.txt)
  — Y's `to=Firing` transition (suppression, not never-fired).
- [`rules/rules.toml`](rules/rules.toml), [`mock/server.py`](mock/server.py).

## Source

- `crates/beacon/src/inhibition.rs` (`InhibitionResolver::observe`: on a
  Firing whose inhibitor is firing, store in `pending`, emit nothing; on
  the inhibitor's Resolved, release the pending Firing).
- `crates/beacon-server/src/main.rs:252-258` hands every emission through
  the shared resolver before the sinks.
- External anchor: `docs/feature/beacon-v0/slices/slice-03-*` (inhibition).

## Notes

The RELEASE half (when X resolves, Y's held Firing is delivered) needs the
mock to flip X's query inactive while keeping Y's active, i.e. a
query-aware mock; not pinned here, noted as the natural B04 follow-on. The
suppressed Firing is held in the resolver's `pending` map; beacon-server
does not emit a dedicated stderr "suppressed" event at v0, so the sink
absence (plus the internal Firing transition) is the observable.
