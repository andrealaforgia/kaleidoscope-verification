# Use-case coverage audit (expectations vs `kaleidoscope-usecases`)

Mapping of the ~253 use cases in `~/dev/kaleidoscope-usecases/README.md`
against the 118 expectations in this catalogue. Honest verdict at the top.

## Verdict

**No — the catalogue does NOT yet cover all the use cases.** It covers the
core strongly (ingest/read, query APIs, durability, beacon, loops) but has
real gaps, the largest being **UC-TIER** (18 CLI tiering UCs almost
entirely unpinned) and a long tail of edge-case UCs (ISO-8601 parsing,
matcher variants, log/trace caps, gateway lifecycle).

Legend: ✅ covered (expectation asserts it) · 🟗 partial (an expectation
touches it but doesn't assert that specific contract) · ❌ GAP, buildable
now (a ✅ E2E-NOW UC with no expectation) · ⏸ blocked/aspirational
(🔭 in the UC catalogue, or pending on N8/N10/N11 harness work).

## Per-domain summary

| Domain | UCs | ✅ covered | 🟗 partial | ❌ gap (buildable) | ⏸ blocked/aspir. |
|---|---|---|---|---|---|
| UC-CLI ingest/read | 15 | 3 (K03,K04) | 4 | 7 | 1 |
| UC-RANGE | 12 | 4 (K06-K08) | 2 | 6 | 0 |
| UC-TIER | 18 | 18 (K14-K24; 2 grounded RED via K18) | 0 | 0 | 0 |
| UC-CLIOBS | 7 | 2 (K05,K10) | 2 | 3 | 0 |
| UC-CLIROB | 8 | 4 (K02,K11,K13,D04/D07) | 2 | 2 | 0 |
| UC-GWLOG | 9 | 2 (LQ02) | 3 | 3 | 1 (HTTP🔭) |
| UC-GWTRC | 7 | 3 (TQ02) | 2 | 2 | 0 |
| UC-GWMET | 7 | 3 (EG01/EG02,Q06) | 1 | 3 | 0 |
| UC-GWTEN | 5 | 1 (LQ07) | 2 | 2 | 0 |
| UC-GWHEALTH | 6 | 2 (G02) | 3 | 1 | 0 |
| UC-GWLIFE | 8 | 1 (G01) | 1 | 6 | 0 |
| UC-MET | 18 | 6 (Q01-Q06) | 2 | 8 | 2 |
| UC-LOG | 19 | 7 (LQ01-LQ07) | 3 | 9 | 0 |
| UC-TRC | 8 | 5 (TQ01-TQ04) | 1 | 2 | 0 |
| UC-LOOP | 9 | 3 (EG01,LQ02,TQ02) | 1 | 4 | 1 (Prism🟡) |
| UC-DUR | 12 | 8 (D01-D20) | 3 | 0 | 1 (cinder-wal not reachable) |
| UC-TEN | 7 | 1 (LQ07) | 1 | 5 | 0 |
| UC-ALR | 11 | 8 (B01-B10) | 1 | 2 | 0 |
| UC-LOOM | 5 | 4 (L01-L06) | 0 | 1 | 0 |
| UC-PRISM | 18 | 1 (Q07) | 0 | 0 | 17 (N11 Playwright) |
| UC-OBS | 5 | 2 (K05/K10/K12) | 2 | 1 | 0 |
| UC-CONF | 4 | 0 | 1 (A07/A08) | 3 | 0 |
| UC-AUTH | 6 | 1 (S03/S07) | 1 (A17 spiffe) | 0 | 4 (aegis-auth in flight + 🔭) |
| UC-SAMP | 3 | 0 | 0 | 0 | 3 (SI01-06 pending N8) |
| UC-SCHEMA | 3 | 1 (X09) | 0 | 0 | 2 |
| UC-PROF | 3 | 1 (D11/D17) | 0 | 0 | 2 (🔭 query) |
| UC-ANOM | 3 | 0 | 0 | 0 | 3 (Augur 🔭) |
| UC-SDK | 6 | 2 (S01,S09) | 2 (S12,S18 pending) | 0 | 2 (🔭) |
| UC-SEC | 4 | 1 (A17) | 0 | 0 | 3 (TLS/SPIFFE 🔭) |
| UC-COST | 7 | 2 (X07,X08) | 1 | 1 | 3 |
| **Total** | **~253** | **~100** | **~45** | **~75** | **~33** |

So roughly **40% of the use cases have a direct expectation**, a fifth are
partially touched, and **~75 are ✅ E2E-NOW UCs with NO expectation yet**
— the buildable backlog. The ⏸ set matches the catalogue's own known-gaps
(Prism/N11, Sieve/N8, aegis-auth in flight, TLS/SPIFFE/Augur aspirational).

**Update 2026-06-06:** the UC-TIER hole is now closed. K14-K24 pin the
whole Cinder tiering command surface (`place`/`migrate`/`get-tier`/
`list-items`/`evaluate-policy`) at HEAD `545a2ba`; 16 GREEN, plus K18
grounding [issue 011](issues/011-cli-unknown-item-diagnostic-leaks-itemid-debug.md)
RED (the unknown-item diagnostic leaks `ItemId("ghost")` vs the documented
`"ghost"`). UC-TIER went from 1 covered / 16 gaps to 18 covered / 0 gaps.

## Highest-value gaps (✅ UCs, buildable now)

1. ~~**UC-TIER-001..018.**~~ CLOSED 2026-06-06 by K14-K24 (see update
   above). Was the single biggest hole; now 18/18 covered.
2. **UC-TEN-002..005 (metrics/traces/tier isolation).** Only logs
   (LQ07) are pinned; the same cross-tenant isolation for query-api,
   trace-query-api and Cinder tiers is unpinned.
3. **UC-GWLIFE gateway drain/shutdown (004/005) + pillar-root (001-003).**
   I have aperture drain (A11-A14) but NOT the `kaleidoscope-gateway`
   binary's SIGTERM/SIGINT drain or pillar-root resolution.
4. **UC-RANGE ISO-8601 edges (009 lowercase z, 010 +00:00, 008 fractional,
   002 half-open, 011 inverted).** CLI `--since/--until` strict-parse
   contracts, each a clean exit-code assertion.
5. **UC-MET matcher variants (003 !=, 005 !~, 006 multi-AND), 007 empty
   success, 014 bad-time-params 400, 017 float epoch.** Q-prefix only
   pins `__name__` equality (Q06), step-ignored (Q03), window cap (Q02),
   bad-promql/regex (Q04/Q05).
6. **UC-LOG edges (003 case-insens severity, 004 unknown-severity 400,
   006/007 body_contains empty/oversized 400, 014 invalid-limit 400, 015
   window cap, 016 result cap, 018 compose).**
7. **UC-LOOP-004 three-pillars-one-stream, 005 log↔trace correlation, 006
   full-platform restart, 008 gateway→query-api→beacon alert.** My beacon
   tests use a mock backend, not the real gateway→query-api→beacon loop.
8. **UC-CLI sub-cases (004 batch 1000, 006 additive, 007 empty read, 009
   CLI tenant isolation, 011 unicode, 013 250-not-÷100, 014 empty-stdin).**
9. **UC-CONF conformance harness (001/002/004).** Untouched.

## Notes on the ⏸ (legitimately not built)

- **Prism runtime (UC-PRISM-001..017 bar 018):** blocked on a
  Playwright-in-container harness (known-gaps N11). Build-side covered by
  X10-X15; same-origin serving by Q07. The rest are 🟡/🔭.
- **Sieve (UC-SAMP):** SI01-SI06 exist `pending`, blocked on N8.
- **Aegis ingest auth (UC-AUTH-002/003):** `aegis-ingest-auth-v0` is in
  flight (DISTILL at `545a2ba`); will be buildable on DELIVER (refuse-to-
  start + at-the-door reject, the A17 pattern).
- **TLS encrypt / SPIFFE / mTLS (UC-SEC-001/003/004), Augur (UC-ANOM),
  Strata query (UC-PROF-002/003):** 🔭 aspirational, not runnable.
- **UC-DUR-010 cinder WAL surfaced:** fixed in code (`e271ddd`) but not
  operator-inducible black-box (ENOSPC doesn't trip the held-page append);
  credited to the in-suite test, see known-gaps.

## Caveat on this audit

"Covered" means an expectation asserts that UC's specific contract.
Several UCs are asserted in spirit by a broader expectation (e.g. UC-DUR-008
fsync is split across D01-D03 process-kill + D08-D14 lying-substrate
refusal, with power-loss honestly out of reach). The per-UC mapping detail
lives in the commit that adds each expectation; this file is the rollup.
