# K33 — cli-roundtrip-field-fidelity

## Surface

`kaleidoscope-cli` operator binary (`ingest`, `read`).

## Behaviour

Round-trip field fidelity beyond K03: `severity_number`/`severity_text`
across the TRACE..FATAL span are preserved; a body with unicode (CJK
`世界`, symbol `✓`) and an escaped control char (tab) is intact; and
records carrying differing `service.name` each keep their own resource
attributes.

Covers **UC-CLI-010** (severity preserved), **UC-CLI-011** (unicode /
escaped-control body), **UC-CLI-012** (resource attributes drive service
identity).

## Source

- External contract anchor: `kaleidoscope-cli` `run_ingest`/`run_read`
  LogRecord serialisation (lossless field round-trip).
- Use-case anchor: `kaleidoscope-usecases` UC-CLI-010/011/012.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`545a2ba`).
- Method: ingest 3 records (TRACE/alpha, FATAL/beta, INFO/gamma with a
  unicode+tab body); read → severities, unicode glyphs, the tab, and each
  record's `service.name` all preserved.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/read.out`](evidence/read.out).

## Issues

None.

## Notes

`.no-compose` marker. Tab check uses a portable `grep -qF "$(printf '\t')"`
(the harness driver runs under BSD grep, no `-P`).
