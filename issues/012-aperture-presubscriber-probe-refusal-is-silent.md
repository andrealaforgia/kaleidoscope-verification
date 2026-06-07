# 012 — aperture's pre-subscriber sink-probe refusal exits silently

- Status: `open` (2026-06-07). Grounded RED by **A21** at kaleidoscope
  HEAD `3532459`. The implementer is already fixing it in
  `aperture-presubscriber-probe-stderr-v0` (DISCUSS at the grounding SHA);
  A21 will flip GREEN on its DELIVER.
- Severity: low (honesty / operability; the fail-closed safety property
  already holds — aperture exits non-zero and binds no listener — only
  the operator-facing reason is missing).
- Surface: `crates/aperture` `run()` startup, sink Earned-Trust probe.
- Opened: 2026-06-07
- Source: flagged by the verifier in message 037 (found while debugging
  the N29 compose auth migration: aperture exited 1 with no logs when
  otelcol-sink was not ready); acknowledged + logged by the implementer
  in message 028 as `aperture-presubscriber-probe-stderr`.

## The gap

`aperture::run()` calls `wire_sink(&config)` — which runs the forwarding
sink's fail-closed Earned-Trust `probe()` — as its FIRST step, BEFORE
`spawn_with_readiness` installs the tracing subscriber. On probe failure
(unreachable downstream) the error is logged via `tracing::error!`, but
with no subscriber yet the line is dropped. The process exits non-zero
with an EMPTY stderr: a fail-closed refusal that says nothing.

## Observed (black-box, A21)

aperture with a valid auth config + a forwarding sink to `192.0.2.1`
(TEST-NET-1, unroutable): `/readyz` never 200 (no listener), exit 1, and
`stderr_bytes=0`. The operator gets a bare non-zero exit with no reason.

## What would make A21 pass

The pre-subscriber probe failure emits a reason on stderr (e.g. an
`event=health.startup.refused` / `sink_probe_failed` line, or a direct
`eprintln!` like the config-validation path uses) naming the
probe/sink/downstream before exiting. A21 asserts this format-agnostically
(non-empty stderr naming the refusal) and flips GREEN on the fix.

## Scope note (verifier)

Reported as a failing expectation about observable behaviour. The fix
shape is the implementer's call; she is already building it.
