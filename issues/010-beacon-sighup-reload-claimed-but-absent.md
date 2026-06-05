# 010 — beacon-server SIGHUP rule reload is documented but absent (silent no-op)

- Status: `open` — grounded black-box by **B03** (RED at `be893c5`).
- Severity: medium (operational; an intended rule reload silently does
  nothing, leaving stale alerting rules with no error to the operator).
- Surface: `beacon-server` signal handling / rule reload.
- Opened: 2026-06-05
- Source: doc-vs-behaviour gap found while building the Beacon harness
  (B03); the four-quadrants "prose overstates the code" theme.

## The documented contract

The Beacon v0 design and slice docs state, repeatedly, that beacon-server
hot-reloads its rule catalogue on SIGHUP:

- `docs/feature/beacon-v0/design/c4-context.md`: "RulesDir -->|loaded on
  start + SIGHUP| Beacon"; "Hot reloading without operator action
  (`SIGHUP` is the boundary)".
- `docs/feature/beacon-v0/design/c4-container.md`: "SIGHUP handler
  triggers Loader reload"; "`beacon_server::signal` | `SIGHUP` reload
  trigger | IO".
- `docs/feature/beacon-v0/slices/slice-02-cue-catalogue.md`: "`SIGHUP`
  triggers reload; the previous catalogue stays active".
- `docs/feature/beacon-v0/discuss/wave-decisions.md` [D3]: "CUE files on
  disk; SIGHUP reload."

The operator-facing promise: edit the rules directory, send SIGHUP, and
the new catalogue takes effect without a restart.

## Observed (black-box, B03)

beacon-server installs handlers for SIGINT (`ctrl_c`) and SIGTERM
(`SignalKind::terminate()`) only (`crates/beacon-server/src/main.rs:177-186`).
Rules are loaded ONCE at startup (`main.rs:164`) and one Tokio task is
spawned per rule (`main.rs:172`); there is no SIGHUP handler and no reload
path. The in-code comment at `main.rs:45` even says "SIGHUP reload arrives
at slice 03" while the slice-02 doc claims it already shipped.

Sending SIGHUP to the running process is a SILENT NO-OP: because
beacon-server runs as PID 1 in its container, the kernel does not apply
SIGHUP's default-terminate disposition (no handler installed), so the
process neither reloads nor stops. B03: start beacon with rule A, add a
rule B to the live rules dir, send SIGHUP, wait — B never begins firing
(the added rule is not picked up) and the process keeps running the
original catalogue, with no reload log and no error.

(Note: outside PID 1 — e.g. under an init/tini — SIGHUP's default
disposition would TERMINATE the process instead, which is arguably worse.)

## The expectation

The observable contract the docs promise: after the rule directory is
edited and SIGHUP is delivered, the new catalogue is in effect (added
rules start ticking, removed rules stop). Observed: SIGHUP changes
nothing. How to resolve is the implementer's call — install the SIGHUP
reload handler the docs describe, or correct the docs to state that v0
loads rules only at startup. This issue states only the observed-vs-
documented behaviour.

## Catalogue impact

Grounded by **B03** (RED at `be893c5`). B03's runner asserts the
documented reload (an added rule fires after SIGHUP); it fails here and
flips GREEN if a SIGHUP reload handler lands. If instead the docs are
corrected to drop the reload claim, B03 is re-framed to pin the
load-once-at-startup behaviour and this issue closes as a doc fix.
