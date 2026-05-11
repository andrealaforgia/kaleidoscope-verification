# X14 — prism-format-check-green

## Surface

Operations / build. Build-engineer-facing.

## Behaviour

`pnpm -F prism format:check` against the kaleidoscope HEAD snapshot exits green.

## Source

- Catalogue-internal addition for the Prism v0 build pipeline.
- External contract anchor:
  [`apps/prism/package.json`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/apps/prism/package.json).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-11 UTC at HEAD.
- Method: `docker run node:22-slim` with the persistent pnpm
  store cache, `pnpm install --frozen-lockfile`, then the
  gate above. The runner asserts the trailing
  `FORMAT_OK` marker.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/X14.stdout.txt`](evidence/X14.stdout.txt) — toolchain log.

## Issues

None.

## Notes

`.no-compose` marker.
