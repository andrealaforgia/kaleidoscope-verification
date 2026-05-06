# Issues

One file per failed or partial expectation, named `NNN-slug.md`. Each issue
links back to the originating expectation and carries a status field
(`open`, `fixed`, `wontfix`).

This file is the single feed point for the kaleidoscope-developing session.

## Open

| Issue | Expectation | Title | Opened |
|---|---|---|---|
| _none yet_ | | | |

## Closed

| Issue | Expectation | Title | Status | Closed |
|---|---|---|---|---|
| _none yet_ | | | | |

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
