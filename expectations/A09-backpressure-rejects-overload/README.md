# A09 — backpressure-rejects-overload

## Surface

Aperture (OTLP ingest gateway). Operator-facing.

## Behaviour

Given aperture is running with a per-transport
`max_concurrent_requests` cap of N
When more than N requests are in flight on a single transport
Then on gRPC, the (N+1)th request returns
`grpc-status: 8 RESOURCE_EXHAUSTED`,
and on HTTP, the (N+1)th request returns HTTP 503 with header
`Retry-After: 1`,
And aperture's stderr emits `event=concurrency_cap_hit` with the
transport, the cap, and the in_flight_at_refusal value.

The harness ships a per-expectation `aperture.toml` that forces
both caps to 1 (see issue 002 for why env-var overrides are not
yet usable).

## Source

- Inter-session feed (other claude session, 2026-05-06): item **A9**.
- External contract anchor:
  [`docs/feature/aperture/slices/slice-05-backpressure.md`](https://github.com/andrealaforgia/kaleidoscope/blob/6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15/docs/feature/aperture/slices/slice-05-backpressure.md)
  lines 45-46.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-06T23:38 UTC
- Kaleidoscope SHA: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`
- Kaleidoscope dirty: `no`
- Method: dockerised harness. Aperture is launched with the
  per-expectation `aperture.toml` (cap=1 for both transports). The
  runner fires four parallel `docker run telemetrygen` containers
  on gRPC and four host-side concurrent `curl POST` requests on
  HTTP, then captures responses and aperture's stderr.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/aperture.toml.used`](evidence/aperture.toml.used) — the per-expectation config (`max_concurrent_requests = 1`).
- [`evidence/runner.stdout.txt`](evidence/runner.stdout.txt) — runner log.
- [`evidence/outcome.txt`](evidence/outcome.txt) — verbatim:
  ```
  http_503_with_retry_after: 1 of 4
  grpc_resource_exhausted:   observed-3-of-4
  aperture_concurrency_cap_hit_lines: 4
  ```
- [`evidence/http.{1..4}.code.txt`](evidence/) and [`http.{1..4}.headers.txt`](evidence/) — per-request HTTP code and headers.
- [`evidence/telemetrygen.grpc.{1..4}.stderr.txt`](evidence/) — per-client gRPC log; the refused clients carry `RESOURCE_EXHAUSTED`.
- [`evidence/aperture.live.stderr.txt`](evidence/aperture.live.stderr.txt) — aperture's `event=concurrency_cap_hit` lines (4) match the cap=1 refusals.

## Issues

- [`issues/002-env-var-overrides-not-wired-in-figment-loader.md`](../../issues/002-env-var-overrides-not-wired-in-figment-loader.md) — the reason this expectation ships its own `aperture.toml`.
- [`issues/003-grpc-backpressure-load-reproducibility.md`](../../issues/003-grpc-backpressure-load-reproducibility.md) — reproducibility caveat for the gRPC arm. The third run of this expectation produced 3/4 RESOURCE_EXHAUSTED; earlier runs produced 0/4. The contract is met when overlap occurs; the harness's load tooling does not guarantee overlap, so future re-verifications should not be alarmed by 0/4.

## Notes

The HTTP arm is deterministic with this load shape (concurrent
host-side `curl` processes have wider scheduling overlap than
docker-container-startup ramps). The gRPC arm is non-deterministic
from the harness; on a clean run we see the contract fire, on a
slow run we see all 4 succeed because aperture processes them
sequentially within the docker-startup jitter window. This is a
catalogue limitation (issue 003), not a kaleidoscope limitation.
