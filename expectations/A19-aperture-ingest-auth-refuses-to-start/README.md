# A19 — aperture-ingest-auth-refuses-to-start

## Surface

`crates/aperture` binary, config/composition boundary. Operator-facing.

## Behaviour

Ingest auth is mandatory — there is no off switch. A missing, incomplete,
or unreadable `[aperture.security.auth.jwt]` block makes aperture REFUSE
TO START: exit 2, `event=config_validation_failed` naming the offending
table / field / path, and no listener bound.

Three refusal shapes, all confirmed:
- absent `[...auth.jwt]` block → `missing [aperture.security.auth.jwt]
  block: ingest auth is mandatory (no off switch); configure
  issuer/audience/secret_file/catalogue_path`;
- block present but missing a required field → names the field
  (`secret_file`);
- `secret_file` pointing at an unreadable path → names the path
  (`/nonexistent/hs256.key`), never any secret bytes.

Covers **UC-AUTH-003** (ingest auth config parsed/validated) and the
refuse-to-start half of **UC-AUTH-002**.

## Source

- External contract anchor: `aegis-ingest-auth-v0`, ADR-0068 DD4, deliver
  `7f72db8` ("fail-closed ingest auth at the door"); aperture
  `config::validate_jwt_auth`.
- Use-case anchor: `kaleidoscope-usecases` UC-AUTH-002/003.

## Verification

- Status: `satisfied`
- Last verified: 2026-06-06 UTC at HEAD (`9817ec9`).
- Method: build aperture from the HEAD snapshot; run it directly against
  three broken auth configs; each exits 2 with `config_validation_failed`
  naming the offender and binds no `/readyz` listener.

## Evidence

- [`evidence/observation.txt`](evidence/observation.txt) — per-fixture readyz/running/exit.
- [`evidence/absent.stderr.txt`](evidence/absent.stderr.txt), [`evidence/missing-field.stderr.txt`](evidence/missing-field.stderr.txt), [`evidence/unreadable.stderr.txt`](evidence/unreadable.stderr.txt).

## Issues

None.

## Notes

`.no-compose`, A17-style self-contained run (does not use the compose
readiness gate, which assumes a binding listener). Companion to **A20**
(the door enforcement). The same mandatory-auth requirement ripples into
the compose harness — see `known-gaps.md` N29.
