# A22 — aperture-ingest-auth-rejects-forged-tokens

## Surface

`crates/aperture` ingest door + `crates/aegis` HS256 validator.
Adversarial auth negative-space.

## Behaviour

A20 proved no-token / junk-string reject and a valid token accepts. A22
attacks the door with WELL-FORMED but illegitimate HS256 JWTs and asserts
aperture rejects every one with `401`:
- `exp` in the past → Expired;
- `alg=none` (no signature) → algorithm not allowed (no alg-confusion
  bypass);
- forged signature (HMAC with the wrong key) → InvalidSignature;
- `tenant_id` not in the catalogue → UnknownTenant (no cross-tenant
  bypass);
- wrong `iss` / wrong `aud` → WrongIssuer / WrongAudience;
- unknown `kaleidoscope_role` → UnknownRole.

A genuinely valid token is the positive control (clears auth → 415 at the
content-type gate). Any 2xx/415 on a forged token would be an auth bypass.

## Source

- External contract anchor: `aegis::Validator::validate` (HS256, exp,
  iss/aud exact-match, catalogue membership, role parse) behind aperture's
  `authenticate()` step.
- Adversarial anchor: the standard JWT attack set (alg-confusion,
  expiry, forged signature, cross-tenant) — the negative space A20 did not
  cover.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-07 UTC at HEAD (`b4ff12a`).
- Method: run aperture with a valid auth config; mint eight tokens (one
  valid + seven forged) and POST each to `/v1/logs`; every forged token →
  401, valid → 415. No bypass.

## Evidence

- [`evidence/codes.txt`](evidence/codes.txt) — per-attack HTTP codes.
- [`evidence/aperture.stderr.txt`](evidence/aperture.stderr.txt) — aegis deny lines.

## Issues

None — the auth held against every attack. A22 is a security regression
guard: a future weakening of the validator (e.g. accidentally accepting
`alg=none` or skipping the exp check) flips it RED.

## Notes

`.no-compose`, A20-style self-contained run. Built from the adversarial
probe after the communication audit flagged that the verifier had not
caught a defect by attacking the implementer's code. The auth proved
sound; the durable value is the regression guard. (One self-caught harness
bug along the way: the first cut minted tokens via a deeply-nested
`echo "$( hit "$( mk ... )" )"`, whose comma/quote-laden JSON mangled the
token — aegis reported `reason=malformed`, not a signature/claim miss, so
the false RED was visibly mine; fixed by minting each token into a var.)
