# Issues

One file per failed or partial expectation, named `NNN-slug.md`. Each issue
links back to the originating expectation and carries a status field
(`open`, `fixed`, `wontfix`).

This file is the single feed point for the kaleidoscope-developing session.

## Open

| Issue | Expectations | Title | Opened |
|---|---|---|---|
| _none_ | | | |

## Closed

| Issue | Expectations | Title | Status | Closed |
|---|---|---|---|---|
| [001](001-aperture-binary-ignores-config-flag.md) | A01, A04 (related); A09, A11, A12, A14, A15, E01-E06 (had been blocking) | aperture binary ignores `--config` (slice-07 not yet wired in `main.rs`) | `fixed` at `6b09c0d` | 2026-05-06 |

## Issue file template

```markdown
# NNN — short title

- Status: `open` | `fixed` | `wontfix`
- Expectation: [<ID>](../expectations/<ID>-<slug>/README.md)
- Opened: YYYY-MM-DD
- Kaleidoscope SHA at observation: <sha>
- Closed: YYYY-MM-DD (if applicable)

## Observed

What we saw. Cite the evidence file(s) under the expectation's `evidence/`.

## Expected

What the expectation says should happen. Quote the relevant clause.

## Reproduction

The exact command(s) to reproduce, plus environment (host arch,
kaleidoscope SHA, dirty state).

## Notes

Hypotheses, links to ADRs or slice docs that bear on the gap.
```
