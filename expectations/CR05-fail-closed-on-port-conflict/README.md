# CR05 — fail-closed-on-port-conflict

## Surface

The consolidated runtime binary (`kaleidoscope`, consolidated-runtime-v0 /
ADR-0076 DD3). Fail-closed startup (wire → probe → use).

## Behaviour

If one of the five listeners cannot bind, the process refuses to start
(`event=health.startup.refused`, non-zero exit) and leaves no half-up serving on
the other listeners.

A robust conflict is forced with two processes:

1. runtime #1 boots and binds 4317/4318/9090/9091/9092 (verified by a real
   `200` on a well-formed range query).
2. runtime #2 boots in #1's network namespace (`--network container:<rt1>`) with
   its own ephemeral pillar root, so it builds/probes its own stores fine and
   then collides on the already-held query ports.
3. runtime #2 exits `1` with
   `{"level":"ERROR","event":"health.startup.refused","reason":"metrics query
   listener bind failed on 0.0.0.0:9090: Address already in use (os error 98)"}`
   — it names the offending listener and reason, serves nothing partial, and the
   incumbent #1 stays up (`200`).

## Source

- kaleidoscope `consolidated-runtime-v0` (`fbcacca`/`2a74e4f`):
  `crates/kaleidoscope-runtime/src/{lib.rs,main.rs}` fail-closed startup (bind
  the query TcpListeners for cheap port-conflict detection, then the ingest
  ports; any bind/probe failure → refuse).
- Contract anchor: ADR-0076 DD3; implementer msg 037 ("FAIL-CLOSED STARTUP").
  Mirrors the per-binary fail-closed posture (Q01/LQ06/TQ04, aperture
  presubscriber probe A21).

## Verification

- Status: `satisfied`
- Grounded GREEN: 2026-06-14 UTC at HEAD `706c852` (runtime code `2a74e4f`).
  `rt_exit=1`, `refused_event=1`, `bind_reason=2`, `rt1_still=200`. The refusal
  reason names `0.0.0.0:9090` + `Address already in use (os error 98)`.
- Transition-proof: RED if #2 stays running (half-up fail-open), exits 0, or
  refuses silently (no reason on the log), or if the incumbent stops serving.
- Method: `harness/run-kaleidoscope-runtime.sh`; the runner boots an incumbent
  runtime, then a second in its netns, polls `docker inspect` for the second's
  exit (bounded, no `timeout`), and checks the exit code + the refusal reason +
  the incumbent's continued `200`.

## Notes

Two runner bugs of mine were caught and fixed before any verdict, neither a
runtime defect: (1) the first attempt used `timeout`, absent on macOS (exit 127,
the runtime never ran); (2) the second used a python blocker whose readiness
check accepted `000` (connection-refused) as up, so no conflict occurred and the
runtime bound 9090 cleanly — I did NOT report a fail-open defect on a conflict
that never happened. The two-runtime-in-one-netns design makes the collision
guaranteed. `.no-compose`: CR05 manages its own runtime containers. This
completes implementer msg 037's attack list (CR01-CR05 + empty-before-ingest).
