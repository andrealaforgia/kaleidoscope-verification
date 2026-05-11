# X11 — prism-typecheck-green

## Surface

Operations / build. Build-engineer-facing.

## Behaviour

`pnpm -F prism typecheck` against the kaleidoscope HEAD snapshot exits green.

## Source

- Catalogue-internal addition for the Prism v0 build pipeline.
- External contract anchor:
  [`apps/prism/package.json`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/apps/prism/package.json)
  (the `scripts` section maps the pnpm filter to the underlying
  toolchain invocation).

## Verification

- Status: `satisfied`
- Last verified: 2026-05-11 UTC at HEAD.
- Method: `docker run node:22-slim` with the persistent pnpm
  store cache, `pnpm install --frozen-lockfile`, then the
  scripted gate above. The runner asserts the trailing
  `TYPECHECK_OK` marker.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/X11.stdout.txt`](evidence/X11.stdout.txt) — full toolchain log.
- [`evidence/X11.stderr.txt`](evidence/X11.stderr.txt) — pnpm progress noise.

## Issues

None.

## Notes

`.no-compose` marker — Prism gates only touch the source tree.
