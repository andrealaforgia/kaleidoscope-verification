# A18 — aperture-serve-loop-death-surfaced-not-zombie

## Surface

`aperture` binary, post-bind serving-loop death surfacing (ADR-0066,
`aperture-serve-loop-error-surfacing-v0`). Operator-facing.

## Behaviour

Given aperture is started with a post-bind serve-loop failure injected for
a transport (the shipped trigger `APERTURE_TEST_INJECT_SERVE_FAILURE=grpc`
or `=http`)
When the serving loop dies after the socket is bound, with no shutdown
requested
Then aperture SURFACES the death rather than leaving a silent zombie: it
emits `event=serve_loop_failed transport=<t>` at ERROR, flips readiness
(`event=readiness_changed ready=false reason=serve_loop_failed`, so
`/readyz` → the sticky `Failed` phase / 503 "failed"), and exits with code
3. The process does NOT keep running as a bound-but-dead listener.

Negative control: with no injection, aperture binds and STAYS UP
(`readiness_changed ready=true`), no `serve_loop_failed` — proving the
exit-3 + events are the death surfacing, not a generic startup failure.

## Why this matters, and why it IS black-box reachable

Before the fix, a serving loop that died after binding was swallowed at
`transport.rs` (`let _ = server.await` / `let _ = axum::serve(...).await`),
so the process kept running with a dead listener — a silent zombie an
operator could not detect (alive process, dead port). The fix folds the
death into the process verdict (exit 3) and the structured event stream.

Unlike the cinder/sluice WAL-write-failure (which has no operator-reachable
induction, so it stays in-suite — see known-gaps), this fix ships a
runtime trigger `APERTURE_TEST_INJECT_SERVE_FAILURE` that routes through
the EXACT production emit + verdict path. That affordance makes the death
black-box reachable end to end, so A18 asserts on the running surface
rather than crediting the in-suite test.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`0f53f3a`). GREEN: grpc and http
  injections each `exit=3`, `running=false`, with
  `event=serve_loop_failed transport=<t>` (ERROR) and
  `readiness_changed ready=false reason=serve_loop_failed`; negative
  control `running=true`, `exit=0`, ready, no `serve_loop_failed`.
- Method: self-contained (`.no-compose`). Builds aperture from the HEAD
  snapshot (`Dockerfile.aperture`), runs it three times with a stub-sink
  config (no otelcol-sink dependency): inject grpc, inject http, and no
  injection. Asserts exit code, the two structured events, and the
  negative-control stay-up.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `0f53f3a`.
- [`evidence/observation.txt`](evidence/observation.txt) — running/exit per run.
- [`evidence/grpc.stderr.txt`](evidence/grpc.stderr.txt),
  [`evidence/http.stderr.txt`](evidence/http.stderr.txt) — the
  `serve_loop_failed` + `readiness_changed` events.
- [`evidence/none.stderr.txt`](evidence/none.stderr.txt) — the negative
  control (ready, no failure).
- [`aperture.toml`](aperture.toml) — stub-sink fixture.

## Source

- `crates/aperture/src/transport.rs` (no longer `let _ = server.await`; the
  serve future's outcome self-reacts), `crates/aperture/src/main.rs:22`
  (exit code 3), `crates/aperture/src/readiness.rs:43` (sticky `Failed` →
  503 "failed"), `crates/aperture/src/lib.rs:269`
  (`APERTURE_TEST_INJECT_SERVE_FAILURE=grpc|http`). ADR-0066, feat
  `d9f0f83`.

## Notes

The `/readyz` 503 is emitted (the readiness flip is in the structured log)
but not externally pollable here: aperture exits 3 within ~1s of the
injected death, so the process is gone before a `/readyz` probe lands.
A18 therefore asserts the `readiness_changed` EVENT (the flip) plus exit 3,
which is the durable, observable proof. Eighteenth aperture expectation;
grounds the zombie-listener fix on the running surface.
