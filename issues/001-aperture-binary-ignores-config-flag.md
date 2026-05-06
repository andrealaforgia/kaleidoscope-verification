# 001 — aperture binary ignores `--config` (slice-07 not yet wired in `main.rs`)

- Status: `open`
- Expectations affected: many (see below); none blocked at the
  pilot stage, but this constrains future verifications.
- Opened: 2026-05-06
- Kaleidoscope SHA at observation: `3d3c99f061a3c76d48ac9d2a824612d8bdc37b68`

## Observed

The aperture binary built from kaleidoscope at the SHA above is
launched by the harness with:

```
aperture --config /etc/aperture/aperture.toml
```

where `aperture.toml` sets `aperture.sink.kind = "forwarding"` and
points the forwarding endpoint at `http://otelcol-sink:4317`. Yet
aperture's stderr in pilot runs A01 and A04 shows:

```
{"event":"sink_accepted","sink":"stub","signal":"traces", ...}
```

That is, the StubSink — not the ForwardingSink — accepted the
records. The downstream otelcol-sink's capture file
(`harness/.captured/otlp-received.jsonl`) remained empty. See for
example [`expectations/A01-otlp-grpc-traces-accepted/evidence/aperture.live.stderr.txt`](../expectations/A01-otlp-grpc-traces-accepted/evidence/aperture.live.stderr.txt).

The cause is in `crates/aperture/src/main.rs` at the snapshot:

```rust
//! Slice 07 lands the `--config <path>` figment-driven loader; the
//! walking-skeleton binary uses defaults so an operator can run
//! `cargo run -p aperture` to exercise the end-to-end shape.
let config = match Config::builder().build() {
    Ok(c) => c,
    Err(e) => { ... }
};
```

`main()` builds a fresh default `Config` and never reads the
`--config` argv. Whatever the operator passes is silently dropped.
The resulting `Config` has `sink_kind = SinkKind::Stub`
(`crates/aperture/src/config/mod.rs:185`).

## Expected

Per ADR-0008 ("Aperture configuration schema and loader: TOML +
figment with forward-compatible TLS/SPIFFE knobs") the binary should
load the file passed via `--config <path>` and apply its values,
emitting `event=config_validation_failed` if validation fails. The
inter-session feed item A15 also expects "`aperture: config error:
...`" to be printed and exit code 2 to be returned when the file is
malformed — both contracts presuppose that `main()` actually reads the
file.

The slice-03 acceptance summary (line 42) and the wave-decisions doc
explicitly use a config path in their demo invocations:
`cargo run -p aperture -- --config examples/config-stub.toml`.

## Reproduction

```
cd ~/dev/kaleidoscope-expectations
git -C ~/dev/kaleidoscope rev-parse HEAD     # confirm 3d3c99f...
./harness/run-expectation.sh A01
cat expectations/A01-otlp-grpc-traces-accepted/evidence/aperture.live.stderr.txt | grep sink_accepted
# Observed: "sink":"stub"
# Expected once slice-07 lands: "sink":"forwarding"
```

## Affected expectations (and how)

- **A01, A04** (and A02, A03, A05, A06 once verified): currently pass
  via the StubSink path. Once slice-07 lands, the harness will
  re-verify with `kind="forwarding"` and expect `sink="forwarding"`
  in the matched stderr line.
- **A09 — backpressure-rejects-overload**: requires a low
  `max_concurrent_requests` to trigger overload deterministically
  with a small client load. The default is 1024, which is hard to
  saturate from a single sidecar.
- **A11, A12, A13 — drain orchestration**: tractable with the
  default `drain_deadline_ms = 30000`, but tightening it for
  deterministic A14 (deadline-exceeded path) requires config.
- **A14 — drain-deadline-exceeded-exit-one**: requires a low
  `drain_deadline_ms` plus an artificially slow handler. Both need
  config.
- **A15 — config-error-pre-init-exit-two**: cannot be exercised at
  this SHA. The binary doesn't try to parse the file, so a malformed
  file produces no error.
- **E01-E06 — round-trip via Spark + Aperture**: cannot be exercised
  end-to-end yet because we cannot point aperture at the otelcol
  downstream sink. The Spark side will hit aperture's StubSink, the
  payload will be acknowledged, but nothing flows to otelcol.

## Notes

This is not a defect in the strict sense. The relevant slices
(slice-07 TLS schema knob; the binary `--config` wiring it folds in)
have not graduated yet. The kaleidoscope project is honest about this
in its own slice docs and main.rs comments — it says "Slice 07 lands
the `--config <path>` figment-driven loader", future tense.

The reason this issue exists in `kaleidoscope-expectations` is to make
the constraint visible to the kaleidoscope-developing session: a
non-trivial slice of the EDD catalogue is gated on slice-07. Once it
lands, this issue closes and the affected expectations get re-verified
in batch.
