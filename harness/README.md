# Harness

The dockerised verification harness for kaleidoscope expectations.

## What it runs

Two services on a single docker compose network.

- **aperture** — built from the live kaleidoscope source tree (path set via
  `KALEIDOSCOPE_DIR` env var, defaults to `~/dev/kaleidoscope`). Listens on
  gRPC `:4317` and HTTP `:4318`. Configured to forward to `otelcol-sink`.
- **otelcol-sink** — the stock `otel/opentelemetry-collector-contrib` image,
  configured to receive OTLP and write everything to
  `/captured/otlp-received.jsonl` via the `file` exporter. This file is the
  ground-truth evidence for forwarding-sink expectations.

The `file` exporter writes one JSON line per received OTLP request. That file
is grep-able, citable verbatim, and version-stable across otelcol releases.

## Why otelcol as the downstream

Three reasons. It is a stable third-party OTLP receiver we did not write, so
its behaviour is not under the kaleidoscope team's control. The `file`
exporter produces a deterministic JSONL artefact. And using a published
upstream image means the harness does not need its own Rust toolchain at run
time, only docker.

## Prerequisites

- Docker 24+ with docker compose v2.17+ (for `additional_contexts` support).
- A clone of `kaleidoscope` at `KALEIDOSCOPE_DIR` (default `~/dev/kaleidoscope`).
- Roughly 2 GB of disk for the cargo build cache layer the first time.

## Usage

```bash
# Run a single expectation by ID. ID is the prefixed code (A01, S03, etc.).
./harness/run-expectation.sh A01

# Override the kaleidoscope source path:
KALEIDOSCOPE_DIR=/somewhere/else ./harness/run-expectation.sh A01
```

The runner does these things, in order:

1. Captures `git rev-parse HEAD` and `git status --porcelain` from
   `KALEIDOSCOPE_DIR`. If the tree is dirty, saves the diff into the
   expectation's `evidence/kaleidoscope-dirty.diff`.
2. Writes `evidence/verification.yaml` with the SHA, dirty flag, UTC
   timestamp, and host info.
3. Brings the harness up: `docker compose up -d --build`.
4. If the expectation directory contains an executable `runner.sh`, runs it
   with the evidence directory as `$1`. The runner is expected to drive the
   actual scenario (send OTLP, hit `/readyz`, signal aperture, etc.) and
   exit non-zero on failure.
5. Captures aperture's container stderr to `evidence/aperture.stderr.txt`,
   the otelcol-sink's stderr to `evidence/otelcol-sink.stderr.txt`, and the
   captured OTLP file to `evidence/otlp-received.jsonl`.
6. Tears the harness down with `docker compose down --volumes`.

The runner writes evidence even when `runner.sh` is absent, so a baseline
"can the dockerised harness boot and reach steady state at this kaleidoscope
SHA?" capture is always available.

## Layout

```
harness/
├── README.md                    this file
├── Dockerfile.aperture          builder + runtime for aperture binary
├── docker-compose.yml           aperture + otelcol-sink wiring
├── otelcol-sink.yaml            otelcol receiver/exporter config
├── aperture.toml                aperture config used by the dockerised binary
├── run-expectation.sh           per-expectation runner
└── .captured/                   transient host bind, gitignored
```

## Notes on reproducibility

The Dockerfile uses `--locked` so the build pins to kaleidoscope's
`Cargo.lock`. The otelcol image is pinned to a specific tag. The runner
records the docker image digests it used so a re-run later can detect
whether the harness moved underneath us.
