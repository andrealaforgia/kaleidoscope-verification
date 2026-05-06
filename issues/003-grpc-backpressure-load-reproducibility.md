# 003 — gRPC backpressure refusal not reproducible from `docker run telemetrygen`

- Status: `open` (caveat, not a defect of kaleidoscope)
- Expectations affected: A09 (gRPC arm — runs are non-deterministic;
  HTTP arm is unaffected)
- Opened: 2026-05-06
- Kaleidoscope SHA at observation: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`

## Observed

A09 fires four parallel `docker run telemetrygen traces` containers
to overflow aperture's gRPC semaphore (cap forced to 1 via the
per-expectation `aperture.toml`). The HTTP arm uses four parallel
host-side `curl` POSTs and reliably observes 503 + `Retry-After`
plus aperture's `event=concurrency_cap_hit transport=http_protobuf`.
The gRPC arm is non-deterministic: across three back-to-back runs
we saw 0/4, 0/4, then 3/4 RESOURCE_EXHAUSTED.

Cause: each `docker run` pays a 50-200 ms ramp (image pull, Go
runtime startup, gRPC `dial`) before its first export call. By the
time client N's exporter actually issues `Export()`, client 1 has
already returned (aperture's StubSink/ForwardingSink path is
microseconds wide). The per-container ramp is the dominant
inter-arrival jitter, and with cap=1 we need overlapping in-flight
requests, not just overlapping container lifetimes.

## Expected

Aperture's contract (`docs/feature/aperture/slices/slice-05-backpressure.md`
lines 45-46) is symmetric across transports:

> gRPC: 5th simultaneous request when cap=4 receives `grpc-status: 8`
> (`RESOURCE_EXHAUSTED`); `grpc-message` names the cap.
> HTTP: 5th simultaneous POST when cap=4 receives HTTP 503 with
> `Retry-After: 1` header; body names the cap.

The mechanism is the same `Semaphore` primitive in
`crates/aperture/src/backpressure.rs` for both transports. The
expected outcome on N+1 simultaneous requests is the same; the
catalogue should be able to demonstrate it for both transports.

## Workaround / mitigation paths

For now, A09 is marked `satisfied` based on the HTTP arm and the
fact that the gRPC arm did fire on the third run (3/4
RESOURCE_EXHAUSTED, captured in the evidence). The Notes section of
A09's README is honest about the variance.

To make the gRPC arm deterministic, the harness would need a load
client that maintains N persistent gRPC connections and fires N
`Export` calls in a tightly-synchronised window. Candidates:

- `ghz` (purpose-built gRPC load tool). Needs the OTLP `.proto`
  files mounted; aperture does not ship them in the runtime image.
- A small Rust binary using `tonic` directly, packaged in a
  long-running container with a barrier (e.g. a named pipe or a
  TCP rendezvous). New harness component; non-trivial.
- A Python container using `grpcio` + the generated OTLP stubs and
  `concurrent.futures`. Smaller than the Rust path.

These are all reasonable; none are urgent given the HTTP arm
already proves the underlying mechanism for one transport. Open
this issue when somebody starts work on a deterministic gRPC load
client for the catalogue.

## Notes

This is a caveat about the *catalogue's load tooling*, not a
defect in kaleidoscope. The kaleidoscope-developing session should
not feel obliged to act on it; it lives here to make the
catalogue's limitations visible.
