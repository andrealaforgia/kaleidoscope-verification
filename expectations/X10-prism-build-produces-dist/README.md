# X10 — prism-build-produces-dist

## Surface

Operations / build. Build-engineer-facing.

## Behaviour

`pnpm install --frozen-lockfile && pnpm -F prism build` against
the kaleidoscope HEAD snapshot produces a populated
`apps/prism/dist/` directory containing the built SPA: at minimum
`index.html` plus an `assets/` subdirectory with the bundled
JavaScript/CSS. This is the build-engineer contract for the Prism
v0 frontend that landed across Slices 01-06 (commits `0dd0988`
through `7e0edcb`).

## Source

- Catalogue-internal addition (post-Prism graduation, 2026-05-11):
  Prism v0 graduated through Slice 06; the build pipeline is
  observable and worth tracking.
- External contract anchor:
  [`apps/prism/package.json`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/apps/prism/package.json)
  `scripts.build = "tsc -b && vite build"`, plus
  [`pnpm-workspace.yaml`](https://github.com/andrealaforgia/kaleidoscope/blob/HEAD/pnpm-workspace.yaml)
  declaring `apps/*` as the workspace root.

## Verification

- Status: `satisfied`
- Last verified: 2026-05-11 UTC at HEAD.
- Method: `docker run node:22-slim` mounting the HEAD snapshot,
  with a persistent pnpm store cache under
  `harness/.workspace-build-cache/pnpm-store/`. Inside the
  container: `corepack enable && corepack prepare pnpm@9.15.0`,
  `pnpm install --frozen-lockfile`, `pnpm -F prism build`, then
  `ls -la apps/prism/dist/`. The runner asserts the listing
  contains `index.html` and an `assets` entry, plus the trailing
  `DONE` marker.

## Evidence

- [`evidence/verification.yaml`](evidence/verification.yaml).
- [`evidence/build.stdout.txt`](evidence/build.stdout.txt) — full pnpm install + build log.
- [`evidence/build.stderr.txt`](evidence/build.stderr.txt) — pnpm progress noise.
- [`evidence/dist-listing.txt`](evidence/dist-listing.txt) — extracted listing of `apps/prism/dist/`.

## Issues

None.

## Notes

The `.no-compose` marker is set: this expectation only touches the
source tree via the node container, no aperture runtime required.

Sibling Prism build-engineer expectations to consider (deferred):
typecheck (`pnpm typecheck`), unit tests (`pnpm vitest run`),
lint (`pnpm lint`), format check (`pnpm format:check`),
bundle-size budget (`pnpm bundle-size`), Playwright e2e
(`pnpm playwright`).
