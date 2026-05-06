# Kaleidoscope Expectations

Expectation-Driven Development (EDD) catalogue for
[kaleidoscope](https://github.com/andrealaforgia/kaleidoscope).

This repository contains *expectations* — descriptions of observable behaviours
that a running kaleidoscope deployment must satisfy. It contains no
kaleidoscope code. Verification is performed by running a dockerised harness
against the kaleidoscope source tree, capturing raw evidence per expectation.

## Why this exists

Kaleidoscope is developed in a parallel session. This repository is the
external observer: a black-box catalogue that asks "does the running system
behave as documented?" and records evidence honestly.

## Methodology

Three rules govern this catalogue.

**1. No claim without verifiable pointer.** An expectation is `satisfied` only
when its evidence section points to one of: a citation `path:line` from the
kaleidoscope tree quoted verbatim; a command we ran with stdout/stderr saved
verbatim to a file in `evidence/`; a test we ran with the exact invocation and
full output saved. No "checked, looks fine".

**2. Pin everything.** Each verification records the kaleidoscope `git
rev-parse HEAD` and `git status --porcelain` at the moment of the check, plus
date, harness commit, and method. Dirty trees are flagged and the diff is
saved into the evidence.

**3. Inter-session feeds are claims, not contracts.** The other session
writing kaleidoscope can feed expectations to this catalogue, but those are
claims to verify. Per expectation we look for an external contract anchor (an
ADR, a distill wave-decision, a slice doc) that predates the verification. If
absent, the expectation is annotated `unanchored-claim` even when the binary
passes.

## Layout

```
.
├── README.md                    methodology + entry point
├── known-gaps.md                explicit non-expectations
├── expectations/
│   ├── INDEX.md                 table of all expectations + status
│   └── <ID>-<slug>/
│       ├── README.md            scenario, source, verification block
│       └── evidence/            raw artefacts (logs, citations, outputs)
├── issues/
│   ├── INDEX.md                 table of open/closed issues
│   └── <NNN>-<slug>.md          one issue per failed expectation
└── harness/
    ├── README.md
    ├── Dockerfile.aperture
    ├── docker-compose.yml
    ├── otelcol-sink.yaml        downstream OTLP receiver -> file exporter
    ├── aperture.toml            aperture config that points at otelcol-sink
    └── run-expectation.sh       runner: SHA pin, compose up, evidence, down
```

## Status legend

| Status | Meaning |
|---|---|
| `pending` | Stubbed, never verified. |
| `satisfied` | Verified with complete evidence. |
| `partial` | Some sub-claims hold, others don't; at least one issue is linked. |
| `broken` | Regression against a previous successful verification; issue linked. |
| `unanchored-claim` | Verifies but no external contract anchor was found; weaker. |
| `out-of-scope` | Removed from scope; reason recorded in the expectation README. |

## Surfaces

The catalogue covers four observable surfaces:

- **A** — Aperture, the OTLP ingest gateway (operator-facing).
- **S** — Spark, the auto-instrumentation SDK (integrator-facing).
- **E** — End-to-end, Spark + Aperture in loopback.
- **X** — Operations, build, supply chain (build-engineer-facing).

The conformance harness library API was considered (H1-H6 in the source feed)
and excluded from the initial scope as a library-consumer concern, not an
end-user behaviour. Re-scoping decision recorded in `known-gaps.md`.

## How to run a verification

```bash
# Default: kaleidoscope is at ~/dev/kaleidoscope.
harness/run-expectation.sh A01

# Or override the source path:
KALEIDOSCOPE_DIR=/path/to/kaleidoscope harness/run-expectation.sh A01
```

The runner records the kaleidoscope SHA + dirty state, brings the dockerised
harness up, executes a per-expectation `runner.sh` if present in the
expectation directory, captures aperture's stderr and the otelcol-sink's
captured OTLP file into `evidence/`, then tears the harness down.

## Pilot status

The first verification pilot covers **A01**, **A04**, and **A10**. The full
catalogue is scaffolded as `pending`. See
[`expectations/INDEX.md`](expectations/INDEX.md) for the live status table.
