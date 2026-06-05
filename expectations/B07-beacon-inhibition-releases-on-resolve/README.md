# B07 — beacon-inhibition-releases-on-resolve

## Surface

Beacon (`beacon-server`), cross-rule inhibition RELEASE (ADR-0035).
Operator-facing. The other half of the inhibition contract: B04 pins the
suppression, B07 pins the release. Reuses the Beacon harness with a
query-aware mock.

## Behaviour

Given X inhibits Y, both Active, X Firing first and then resolving (its
condition clears)
When beacon-server evaluates them
Then Y's Firing — suppressed while X was Firing — is RELEASED to Y's sinks
once X resolves. The suppressed alert is DEFERRED, not lost: it arrives
only after the inhibitor clears.

## How the test is made deterministic

The mock is query-aware: X's query (`up == 0`) is Active for
`FIRING_WINDOW=9s` then Inactive (X fires, then resolves); Y's query
(`latency_seconds > 1`) is Active throughout. X has `for_duration=0s`
(fires on the first tick); Y has `for_duration=3s` so it reaches Firing
WHILE X is already Firing (suppressed, as in B04), rather than racing X at
the same tick. When X's query goes Inactive, X resolves and the
`InhibitionResolver` releases Y's held Firing. The webhook records a
delivery timestamp per incident so the runner asserts ORDER, not just
presence.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-05 UTC at HEAD (`a62b29a`). GREEN. Webhook
  delivery sequence (t = seconds since mock start):
  ```
  t=3.03  b07-x-inhibitor  firing
  t=9.03  b07-x-inhibitor  resolved
  t=9.04  b07-y-inhibited  firing      <- released after X resolved
  ```
  Y produced NO firing between t=3 and t=9 (suppressed), then was released
  at t=9.04, immediately after X resolved at t=9.03.
- Method: self-contained (`.no-compose`). beacon-server + a query-aware
  mock (backend + catcher) on a throwaway docker network; asserts X fired,
  X resolved, and Y's Firing was delivered with `t >= X-resolve t`.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `a62b29a`.
- [`evidence/incidents.ndjson`](evidence/incidents.ndjson) — the
  timestamped delivery sequence.
- [`rules/rules.toml`](rules/rules.toml), [`mock/server.py`](mock/server.py).

## Source

- `crates/beacon/src/inhibition.rs` (`observe` on `Resolved`: "for every
  rule this rule inhibits, if it has a pending Firing and no other
  inhibitor is Firing, release it now").
- `crates/beacon-server/src/main.rs:252-258` routes every emission through
  the shared resolver.

## Notes

Completes the inhibition story with
[B04](../B04-beacon-server-inhibition-collapses-storm/README.md). Together
they show the storm-collapse is safe: while the upstream is firing,
downstream alerts are held (B04); when it clears, the held alert is
delivered, not silently dropped (B07). The first run of B07 failed
honestly — both rules at `for_duration=0s` raced at the same tick and Y
was not suppressed; fixed by the same dwell-ordering B04 uses.
