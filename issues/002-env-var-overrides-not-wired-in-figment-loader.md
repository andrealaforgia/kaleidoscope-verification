# 002 — env-var overrides not wired in `Config::from_toml_path`

- Status: `fixed`
- Expectations affected: A09 (workaround removed; now uses
  `.env-overrides`), and any future expectation that wants to
  override one config value without shipping a full
  `aperture.toml`.
- Opened: 2026-05-06
- Closed: 2026-05-07 at SHA `c8d8a55` ("fix(aperture): wire env-var
  override layer per ADR-0008").
- Kaleidoscope SHA at observation: `6b09c0d4eb38fc2e83a4fc8cf3f9bad6d9813b15`

## Observed

ADR-0008 declares the loader contract:

> **Loader**: `figment` (caret `^0.10`) with `Toml::file(path)` +
> `Env::prefixed("APERTURE__")` providers, in that order (file
> first, env overrides file).
>
> Environment-variable overrides use `APERTURE__` prefix and `__`
> as the path separator (figment's standard convention):
> `APERTURE__TRANSPORT__GRPC__BIND_ADDR=0.0.0.0:14317`,
> `APERTURE__SINK__KIND=forwarding`, ...

(`docs/product/architecture/adr-0008-aperture-configuration-schema.md`,
"Decision" section.)

The loader implementation at SHA `6b09c0d` only merges `Toml::file`:

```rust
// crates/aperture/src/config/mod.rs:62-69
pub fn from_toml_path(path: impl AsRef<Path>) -> Result<Self, ConfigError> {
    let raw: RawConfig = Figment::new()
        .merge(figment::providers::Toml::file(path.as_ref()))
        .extract()
        .map_err(|e| ConfigError(format!("config parse failed: {e}")))?;
    raw.into_config()
}
```

No `Env::prefixed("APERTURE__")` provider is merged. Setting
`APERTURE__TRANSPORT__GRPC__MAX_CONCURRENT_REQUESTS=1` on aperture's
container has no effect; the value from the TOML file (or the schema
default, if the TOML omits it) wins. We confirmed this directly: the
env var reaches the container (`docker compose exec aperture env`
shows it) but aperture continues to use the TOML / default value.

## Expected

Per ADR-0008: when an env var is set with the documented prefix and
separator, it overrides the corresponding TOML field at config-load
time, and `Config::from_toml_path` returns a `Config` reflecting
the override. A non-trivial slice of the EDD catalogue's
flexibility hinges on this mechanism (per-expectation knob without
shipping a per-expectation TOML).

## Reproduction

Bring up the harness with an env override and inspect the live
behaviour:

```
APERTURE__TRANSPORT__GRPC__MAX_CONCURRENT_REQUESTS=1 \
KALEIDOSCOPE_DIR=~/dev/kaleidoscope-expectations/harness/.snapshot \
docker compose -f harness/docker-compose.yml up -d --build
docker compose -f harness/docker-compose.yml exec aperture env | grep APERTURE__
# APERTURE__TRANSPORT__GRPC__MAX_CONCURRENT_REQUESTS=1   <-- present
# Send 4 concurrent requests, observe that aperture's `cap=1` semaphore
# does NOT refuse anything; cap is in fact still 16 (the value from
# harness/aperture.toml).
```

## Workaround in this catalogue

Until the loader merges `Env::prefixed`, expectations that need a
non-default config ship a per-expectation `aperture.toml` and the
harness mounts it instead of the default via the
`APERTURE_TOML` compose variable. See
`harness/run-expectation.sh` (the "per-expectation aperture.toml"
block) and `expectations/A09-backpressure-rejects-overload/aperture.toml`
for the live example.

The `.env-overrides` mechanism in `harness/run-expectation.sh` is
kept in place for the day this issue is fixed: the file is sourced
into the compose call's environment and the relevant env vars are
listed (without values) in `docker-compose.yml`'s aperture
`environment:` block, ready to pass through.

## Notes

This is structurally similar to issue 001: an ADR specifies a
contract, the implementation didn't yet honour it. The catalogue's
job is to make the gap visible and to document the workaround until
the slice that wires it lands.

## Resolution

The fix landed at kaleidoscope `c8d8a55`
("fix(aperture): wire env-var override layer per ADR-0008").
`Config::from_toml_path` now merges the `Env::prefixed("APERTURE__")`
provider on top of `Toml::file`, so an env var beats the file per
ADR-0008.

## Verification at fix

A09 was switched from the per-expectation `aperture.toml`
workaround to a single-file `.env-overrides` carrying:

```
APERTURE__TRANSPORT__GRPC__MAX_CONCURRENT_REQUESTS=1
APERTURE__TRANSPORT__HTTP__MAX_CONCURRENT_REQUESTS=1
```

Re-verification at HEAD post-fix:

- `aperture_concurrency_cap_hit_lines: 4`
- HTTP arm: 1 of 4 returned 503 with Retry-After header.
- gRPC arm: 3 of 4 returned RESOURCE_EXHAUSTED.

The cap=1 is taking effect from the env var alone; no per-
expectation `aperture.toml` is shipped. The `aperture.toml` from
A09 was removed in the same change set that closes this issue.
The catalogue's `.env-overrides` machinery is now the canonical
way to pin per-expectation knobs.
