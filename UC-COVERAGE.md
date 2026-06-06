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
| UC-CLI ingest/read | 15 | 15 (K03,K04,K29-K33) | 0 | 0 | 0 |
| UC-RANGE | 12 | 12 (K06-K09,K25-K28) | 0 | 0 | 0 |
| UC-TIER | 18 | 18 (K14-K24; K18 flipped GREEN at ddbe982) | 0 | 0 | 0 |
| UC-CLIOBS | 7 | 6 (K05,K10,K34) | 0 | 0 | 1 (006 🟡 dogfood) |
| UC-CLIROB | 8 | 4 (K02,K11,K13,D04/D07) | 2 | 2 | 0 |
| UC-GWLOG | 9 | 7 (LQ02,LQ04,LQ05,LQ10,D01) | 1 (007 🟡) | 0 | 1 (009 HTTP🔭) |
| UC-GWTRC | 7 | 6 (TQ02,TQ06,TQ07,D03) | 0 | 1 (007 multi-service) | 0 |
| UC-GWMET | 7 | 5 (EG01/EG02,EG03,Q10,D02) | 0 | 1 (005 timestamps) | 1 (007 🟡) |
| UC-GWTEN | 5 | 5 (EG04,LQ02,G07,Q08,LQ07) | 0 | 0 | 0 |
| UC-GWHEALTH | 6 | 3 (G02,G06) | 3 | 0 | 0 |
| UC-GWLIFE | 8 | 5 (G01,G04,G05) | 1 (006 🟡) | 1 (008 RUST_LOG) | 1 (003 image-pinned) |
| UC-MET | 18 | 15 (Q01-Q06,Q09,Q10,EG01) | 1 (008 half-open) | 0 | 2 (011 cap,015 store-500) |
| UC-LOG | 19 | 18 (LQ01-LQ09) | 0 | 0 | 1 (016 result-cap >100k not reachable) |
| UC-TRC | 8 | 8 (TQ01-TQ06) | 0 | 0 | 0 |
| UC-LOOP | 9 | 7 (EG01,LQ02,TQ02,EG05,EG06,EG07,B02) | 1 (009 triage) | 0 | 1 (007 Prism🟡) |
| UC-DUR | 12 | 8 (D01-D20) | 3 | 0 | 1 (cinder-wal not reachable) |
| UC-TEN | 7 | 4 (LQ07,Q08,TQ05,K23) | 2 | 1 | 0 |
| UC-ALR | 11 | 8 (B01-B10) | 1 | 2 | 0 |
| UC-LOOM | 5 | 4 (L01-L06) | 0 | 1 | 0 |
| UC-PRISM | 18 | 1 (Q07) | 0 | 0 | 17 (N11 Playwright) |
| UC-OBS | 5 | 2 (K05/K10/K12) | 2 | 1 | 0 |
| UC-CONF | 4 | 0 | 1 (A07/A08) | 3 | 0 |
| UC-AUTH | 6 | 3 (A19,A20,S03/S07) | 0 | 0 | 3 (🔭 RBAC/audit/SSO) |
| UC-SAMP | 3 | 0 | 0 | 0 | 3 (SI01-06 pending N8) |
| UC-SCHEMA | 3 | 1 (X09) | 0 | 0 | 2 |
| UC-PROF | 3 | 1 (D11/D17) | 0 | 0 | 2 (🔭 query) |
| UC-ANOM | 3 | 0 | 0 | 0 | 3 (Augur 🔭) |
| UC-SDK | 6 | 2 (S01,S09) | 2 (S12,S18 pending) | 0 | 2 (🔭) |
| UC-SEC | 4 | 1 (A17) | 0 | 0 | 3 (TLS/SPIFFE 🔭) |
| UC-COST | 7 | 2 (X07,X08) | 1 | 1 | 3 |
| **Total** | **~253** | **~175** | **~25** | **~18** | **~35** |

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
The same day, UC-TEN cross-tenant isolation was extended beyond logs:
**Q08** (metrics via query-api) and **TQ05** (traces via trace-query-api)
join LQ07 (logs) and K23 (tier state), each proving isolation-not-absence
with a same-store control. UC-TEN went 1→4 covered, 5→1 gap. And **K25-K28** closed the UC-RANGE
parse/window edges (strict ISO-8601, half-open `[since, until)`,
inverted-empty, empty-tenant stats), taking UC-RANGE to 12/12. And **K29-K33** closed the UC-CLI ingest/read
sub-cases (batch no-loss, additive, empty-stdin/read-empty, tenant
isolation, field fidelity), taking UC-CLI to 15/15. Three full domains
now closed in a day: UC-TIER, UC-RANGE, UC-CLI.

## Highest-value gaps (✅ UCs, buildable now)

1. ~~**UC-TIER-001..018.**~~ CLOSED 2026-06-06 by K14-K24 (see update
   above). Was the single biggest hole; now 18/18 covered.
2. ~~**UC-TEN-002..004 (metrics/traces/tier isolation).**~~ CLOSED
   2026-06-06: Q08 (metrics, query-api), TQ05 (traces, trace-query-api)
   and K23 (tier state) join LQ07 (logs). UC-TEN-006 (per-instance tenant
   binding) is demonstrated in passing by all three env-var-bound
   instances. Remaining: UC-TEN-005 (same metric name both-populated,
   partial via Q08) and UC-TEN-007 (default-tenant fallback no-leak).
3. **UC-GWLIFE gateway drain/shutdown (004/005) + pillar-root (001-003).**
   I have aperture drain (A11-A14) but NOT the `kaleidoscope-gateway`
   binary's SIGTERM/SIGINT drain or pillar-root resolution.
4. ~~**UC-RANGE ISO-8601 edges.**~~ CLOSED 2026-06-06 by K25-K28 (strict
   parse, half-open, inverted-empty, empty-tenant stats). UC-RANGE 12/12.
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
8. ~~**UC-CLI sub-cases.**~~ CLOSED 2026-06-06 by K29-K33 (batch no-loss,
   additive, empty-stdin/read-empty, tenant isolation, field fidelity).
   UC-CLI now 15/15.
9. **UC-CONF conformance harness (001/002/004).** Untouched.

## Notes on the ⏸ (legitimately not built)

- **Prism runtime (UC-PRISM-001..017 bar 018):** blocked on a
  Playwright-in-container harness (known-gaps N11). Build-side covered by
  X10-X15; same-origin serving by Q07. The rest are 🟡/🔭.
- **Sieve (UC-SAMP):** SI01-SI06 exist `pending`, blocked on N8.
- **Aegis ingest auth (UC-AUTH-002/003):** DELIVERED 2026-06-06
  (`7f72db8`) and now COVERED by **A19** (refuse-to-start) and **A20**
  (door enforcement: 401 reject + WWW-Authenticate challenge, valid-JWT
  accept). Mandatory auth ripples into the compose harness — see
  `known-gaps.md` N29 (A01-A16 pending re-verification + migration).
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
