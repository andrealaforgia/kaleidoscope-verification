# A15 — config-error-pre-init-exit-two

## Surface

Aperture (OTLP ingest gateway). Operator-facing.

## Behaviour

Given a malformed `aperture.toml` (a value that fails the figment
loader's typed schema, e.g. a non-parseable socket address)
When aperture is invoked with `--config <that-path>`
Then aperture writes `aperture: config error: <message>` to stderr
(direct, pre-tracing-subscriber write — this is the only stderr
write path that bypasses tracing)
And exits with code 2.

## Source

- Inter-session feed (other claude session, 2026-05-06): item **A15**.
- External contract anchor:
  [`docs/product/architecture/adr-0008-aperture-configuration-schema.md`](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/docs/product/architecture/adr-0008-aperture-configuration-schema.md)
  Decision section ("Failure returns `ApertureError::ConfigInvalid`
  with a specific message; exit code 2; stderr `event=config_validation_failed`").

## Verification

- Status: `satisfied`
- Last verified: 2026-05-27 UTC at HEAD (`34131c9`) — cycle 8
  cold retry GREEN after a flake on the first attempt (same
  `/readyz` timeout pattern as the closed-as-flake issues 006
  and 007; no new issue opened per the established
  disposition).
- Earlier satisfaction: 2026-05-06T23:32 UTC at HEAD `6b09c0d`.
- Kaleidoscope dirty: `no`
- Method: the runner writes a malformed TOML file with
  `bind_addr = "this-is-not-a-valid-socket-addr"`, runs a one-off
  `docker run kaleidoscope-expectations/aperture:under-test --config /etc/aperture/aperture.toml`
  with that file mounted, captures stdout / stderr / exit code,
  and asserts exit 2 plus the literal stderr prefix
  `aperture: config error: `.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/malformed-aperture.toml`](evidence/malformed-aperture.toml) — the input.
- [`evidence/aperture.oneshot.exit-code.txt`](evidence/aperture.oneshot.exit-code.txt) — `2`.
- [`evidence/aperture.oneshot.stderr.txt`](evidence/aperture.oneshot.stderr.txt) — verbatim:
  `aperture: config error: config parse failed: invalid socket address syntax for key "default.aperture.transport.grpc.bind_addr" in etc/aperture/aperture.toml TOML file`.

## Issues

None.

## Notes

The contract anchor mentions `event=config_validation_failed` as
the post-init structured-tracing form of the same failure; at this
SHA, with the binary's main() path going through a pre-init `eprintln!`,
no structured event is emitted on the failure path. That is
consistent with the `--config` wiring landed in `6b09c0d`. If a
future slice routes the load failure through tracing post-init,
this expectation gets re-verified with the structured form too.
