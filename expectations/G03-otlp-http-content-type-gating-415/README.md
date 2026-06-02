# G03 — otlp-http-content-type-gating-415

## Surface

kaleidoscope-gateway OTLP/HTTP transport (aperture-embedded, :4318).
Operator/integrator-facing input validation.

## Behaviour

The gateway's OTLP/HTTP endpoint gates STRICTLY on `Content-Type`,
BEFORE any body parsing:

- `application/json` → `415 Unsupported Media Type`;
- `application/x-protobuf-foo` (a lookalike) → `415` — it is NOT
  conflated with the real OTLP media type, i.e. no lax `starts_with`
  match;
- the correct `application/x-protobuf` with a non-protobuf body → `400`
  (it passes the content-type gate, then fails body decode), NOT `415`.
  The control proves the 415 is content-type-specific, not a blanket
  rejection of unusual requests.

## Source

- Motivated by the four-quadrants report (Q1): "Strict content-type
  gating: `application/json` and lookalikes like
  `application/x-protobuf-foo` are rejected with 415, no lax
  `starts_with`."
- Code: `crates/aperture/src/transport.rs` `is_protobuf_content_type`
  (unit tests confirm json/empty/missing are rejected and
  `application/x-protobuf-foo` is not conflated). The gateway embeds
  this transport on :4318.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-02 UTC at HEAD (`b286cb4`, clean tree). GREEN at
  first attempt (after a catalogue-side fix — the first draft used
  null-byte binary bodies that bash truncated; content-type gating runs
  before body parsing, so plain ASCII bodies are sufficient and avoid
  the quoting trap). `code_json=415`, `code_lookalike=415`,
  `code_badpb=400`.
- Method: `harness/run-gateway.sh` builds the gateway image; `docker
  run -d` on a UNIQUE high host port (`14330`, N27); three `curl -X
  POST` calls to `/v1/metrics` with the three content types.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml) — SHA `b286cb4`.
- [`evidence/G03.stdout.txt`](evidence/G03.stdout.txt) — the three HTTP codes.
- [`evidence/gateway.stderr.txt`](evidence/gateway.stderr.txt) — the
  gateway's container log during the run.

## Issues

None. This is a Q1 (correct-behaviour) confirmation; it pins a strict
input-validation property the four-quadrants report praised, as a
regression guard against a future lax `starts_with` creeping in.

## Notes

Third G-prefix expectation (G01 lifecycle, G02 fsync-probe refusal, G03
content-type gating). Unique high host port (`14330`) per N27.
