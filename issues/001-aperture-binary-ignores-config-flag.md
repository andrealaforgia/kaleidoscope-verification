# 001 — aperture binary ignores `--config` (slice-07 not yet wired in `main.rs`)

- Status: `fixed`
- Expectations affected: many (see below); none blocked at the
  pilot stage, but this constrained future verifications until the
  fix landed.
- Opened: 2026-05-06
- Closed: 2026-05-06 (UTC) at SHA
  `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
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
had not graduated when the issue was raised. The kaleidoscope project
was honest about this in its own slice docs and main.rs comments —
"Slice 07 lands the `--config <path>` figment-driven loader",
future tense.

The reason this issue existed in `kaleidoscope-expectations` was to
make the constraint visible to the kaleidoscope-developing session: a
non-trivial slice of the EDD catalogue was gated on the wiring.

## Resolution

Two-step fix-forward, fed back from this catalogue:

1. Commit `1075462` ("fix(aperture): wire --config <path> argv parsing
   into the binary") was empty: the message described the fix in
   detail but the commit's tree was identical to its parent. The
   actual main.rs changes were sitting unstaged in the working tree
   at the time of `git commit`. `git archive HEAD` produced the
   pre-fix `main.rs` and the harness re-verification at that SHA
   showed the same `sink="stub"` outcome as the original observation.
2. Commit `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
   ("fix(aperture): wire --config <path> argv parsing — actual
   changes (retry)") landed the real diff: 131 lines in main.rs
   (parse_argv, --config / --help branches, exit code 2 paths, five
   unit tests for the argv parser) plus a docstring fix in
   config/mod.rs and a slice-08-completion post-merge note.

## Verification at fix

Pilot batch re-run at SHA `6b09c0d`:

- **A01** (OTLP/gRPC traces accepted on :4317): aperture's
  `event=sink_accepted` now reads
  `sink="forwarding" downstream="http://otelcol-sink:4318" downstream_latency_ms=2`.
  The otelcol-sink's file-exporter capture
  ([`expectations/A01-otlp-grpc-traces-accepted/evidence/otlp-received.jsonl`](../expectations/A01-otlp-grpc-traces-accepted/evidence/otlp-received.jsonl))
  is non-empty (984 bytes) and contains the
  `service.name=expectation-A01-pilot` resourceSpans. End-to-end
  forwarding chain proven independently of aperture's own stderr.
- **A04** (OTLP/HTTP/protobuf traces accepted on :4318): same shape,
  `sink="forwarding"`, downstream capture present
  ([`expectations/A04-otlp-http-protobuf-traces-accepted/evidence/otlp-received.jsonl`](../expectations/A04-otlp-http-protobuf-traces-accepted/evidence/otlp-received.jsonl)).
- **A10** (`/readyz=200`): unaffected by this issue, re-verified
  green at the new SHA.

## Adjustment to the harness, made during this resolution

The harness's `aperture.toml` initially pointed `forwarding.endpoint`
at `http://otelcol-sink:4317` — the otelcol-sink's gRPC port.
ForwardingSink speaks OTLP/HTTP/protobuf
(`POST <endpoint>/v1/{logs,traces,metrics}`), so the correct port is
`4318`, the otelcol-sink's HTTP port. The endpoint was corrected to
`http://otelcol-sink:4318` in the same change set that closed this
issue. The mismatched-endpoint failure mode produced exit code 1
with no aperture stderr (the probe failed before the tracing
subscriber initialised). Worth knowing for future issues.
