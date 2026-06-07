# A21 — aperture-presubscriber-probe-refusal-is-loud

## Surface

`crates/aperture` binary, startup sink-probe failure path. Operator-facing.

## Behaviour (desired contract)

A fail-closed sink-probe refusal must SAY SOMETHING on stderr — it must
not exit silently. aperture's forwarding sink runs a fail-closed
Earned-Trust probe as the FIRST step of `run()`, BEFORE the tracing
subscriber is installed. When the downstream is unreachable the probe
refuses: aperture exits non-zero and binds no listener (good), but the
refusal reason is logged through `tracing`, which has no subscriber yet,
so it is dropped — the operator sees a bare exit 1 with no line.

## Source

- External contract anchor: `aperture-presubscriber-probe-stderr-v0`
  (in flight; DISCUSS at `3532459`) — the implementer's fix for the
  silent pre-subscriber refusal, which I flagged in message 037 and she
  logged in message 028.
- Use-case anchor: the Earned-Trust / fail-closed honesty principle (a
  refusal that says nothing is half a refusal).

## Verification

- Status: `broken` — grounds [issue 012](../../issues/012-aperture-presubscriber-probe-refusal-is-silent.md).
- Last verified: 2026-06-07 UTC at HEAD (`3532459`).
- Method: run aperture with a valid auth config whose forwarding sink
  points at an unreachable downstream (`192.0.2.1`, TEST-NET-1); the probe
  refuses → exit 1, no `/readyz` listener, and **0 bytes of stderr**.

## Observed vs desired

Fail-closed already holds: exit 1, no listener. The message assertion is
RED because the refusal is silent (`stderr_bytes=0`). Transition-proof: it
asserts the desired contract (a non-empty reason naming the
probe/sink/refusal) format-agnostically, so it flips GREEN unchanged once
aperture prints any pre-subscriber refusal line on probe failure.

## Evidence

- [`evidence/observation.txt`](evidence/observation.txt) — readyz/running/exit/stderr_bytes.
- [`evidence/aperture.stderr.txt`](evidence/aperture.stderr.txt) — empty at the grounding SHA.

## Issues

- [012](../../issues/012-aperture-presubscriber-probe-refusal-is-silent.md) — the pre-subscriber sink-probe refusal exits silently.

## Notes

`.no-compose`, A17/A19/A20-style self-contained run. Low severity (the
fail-closed safety property holds; only the operator line is missing).
Built on A20's auth fixtures + a forwarding sink to an unroutable address.
