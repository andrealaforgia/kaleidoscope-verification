#!/usr/bin/env bash
# QA01 — the deployed query-api binary REFUSES TO START on a broken
# read-auth config (the negative startup probe, read-path-query-api-auth-v0
# slice 3a, ADR-0074 DD1/DD4). Two boots, both black-box on the real image:
#
#  (A) PARTIAL config — some but not all four KALEIDOSCOPE_QUERY_AUTH_* keys
#      set. The binary must exit 2 (EXIT_CONFIG_ERROR) and emit
#      event=config_validation_failed naming the MISSING keys, before it
#      binds the listener.
#  (B) UNREADABLE secret_file — all four keys set but the secret_file PATH
#      does not exist. The binary must exit 2 with config_validation_failed
#      naming the offending PATH and the io error class, and must NOT print
#      any secret byte.
#
# Contract: resolve_read_auth (composition.rs) returns Err on partial /
# unreadable / unloadable; main.rs maps that to event=config_validation_failed
# + ExitCode::from(2). A clean GREEN proves the half-configured auth set is a
# loud refuse-to-start, not a silent fall-through to no-auth (the open-by-
# default trap).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

# A real secret value we will mount for boot B; the assertion proves it is
# NEVER echoed back in the refusal output (redaction).
SECRET_SENTINEL="qa01-secret-sentinel-do-not-leak"
printf '%s' "$SECRET_SENTINEL" > "$EVIDENCE_DIR/jwt.secret.fixture"

INLINE='
run_qapi() { # $1=label ; remaining args = extra docker -e/-v flags
    local label="$1"; shift
    local ec=0
    docker run --rm \
        -v "$DATA_HOST:/data" \
        -e RUST_LOG=info \
        "$@" \
        "$QAPI_IMAGE" > "/tmp/${label}.out" 2> "/tmp/${label}.err" || ec=$?
    echo "${label}_exit=$ec"
    cp "/tmp/${label}.err" "'"$EVIDENCE_DIR"'/${label}.stderr.txt"
    cp "/tmp/${label}.out" "'"$EVIDENCE_DIR"'/${label}.stdout.txt"
}

# (A) partial: ISSUER + AUDIENCE set, SECRET_FILE + CATALOGUE missing.
run_qapi partial \
    -e KALEIDOSCOPE_QUERY_AUTH_ISSUER=kaleidoscope-harness \
    -e KALEIDOSCOPE_QUERY_AUTH_AUDIENCE=kaleidoscope-query

# (B) unreadable secret_file: all four set, secret_file PATH absent in the
# container (we deliberately do NOT mount it).
run_qapi unreadable \
    -e KALEIDOSCOPE_QUERY_AUTH_ISSUER=kaleidoscope-harness \
    -e KALEIDOSCOPE_QUERY_AUTH_AUDIENCE=kaleidoscope-query \
    -e KALEIDOSCOPE_QUERY_AUTH_SECRET_FILE=/auth/absent-secret \
    -e KALEIDOSCOPE_QUERY_AUTH_CATALOGUE=/auth/absent-catalogue.toml
'
"$HARNESS_DIR/run-query-api.sh" "$EVIDENCE_DIR" QA01 "$INLINE"

fail() { echo "FAIL: $1" >&2; exit 1; }

# ---- (A) partial config ----
PEC=$(grep -oE 'partial_exit=[0-9]+' "$EVIDENCE_DIR/QA01.stdout.txt" | tail -1 | cut -d= -f2)
PERR="$EVIDENCE_DIR/partial.stderr.txt"
[[ "$PEC" == "2" ]] || fail "partial config: expected exit 2 (EXIT_CONFIG_ERROR); got $PEC"
EV=$(grep '"event":"config_validation_failed"' "$PERR" | head -1)
[[ -n "$EV" ]] || { echo "partial stderr:" >&2; cat "$PERR" >&2; fail "partial config: no structured event=config_validation_failed on stderr"; }
echo "$EV" | jq -e '.level=="ERROR"
    and (.reason|contains("partial read-auth config"))
    and (.reason|contains("KALEIDOSCOPE_QUERY_AUTH_SECRET_FILE"))
    and (.reason|contains("KALEIDOSCOPE_QUERY_AUTH_CATALOGUE"))' >/dev/null \
    || { echo "$EV" >&2; fail "partial config: config_validation_failed reason does not name BOTH missing keys at ERROR level"; }
# It must NOT have bound a listener / reached the serve loop.
grep -q '"event":"listener_bound"' "$PERR" && fail "partial config: bound a listener despite the bad config (should refuse before bind)"
echo "OK (A) partial: exit 2, config_validation_failed names the two missing keys, no listener bound"

# ---- (B) unreadable secret_file ----
UEC=$(grep -oE 'unreadable_exit=[0-9]+' "$EVIDENCE_DIR/QA01.stdout.txt" | tail -1 | cut -d= -f2)
UERR="$EVIDENCE_DIR/unreadable.stderr.txt"
[[ "$UEC" == "2" ]] || fail "unreadable secret_file: expected exit 2; got $UEC"
EV2=$(grep '"event":"config_validation_failed"' "$UERR" | head -1)
[[ -n "$EV2" ]] || { cat "$UERR" >&2; fail "unreadable secret_file: no structured event=config_validation_failed"; }
echo "$EV2" | jq -e '.level=="ERROR"
    and (.reason|contains("/auth/absent-secret"))
    and (.reason|test("unreadable|No such file|NotFound|not found"))' >/dev/null \
    || { echo "$EV2" >&2; fail "unreadable secret_file: reason does not name the PATH + io error class"; }
# Redaction: the secret sentinel bytes must never appear in any refusal output.
if grep -q "$SECRET_SENTINEL" "$UERR" "$EVIDENCE_DIR/unreadable.stdout.txt" "$PERR"; then
    fail "a secret sentinel byte leaked into the refusal output (redaction breach)"
fi
echo "OK (B) unreadable: exit 2, config_validation_failed names the PATH + io class, no secret leak"

echo "QA01 satisfied — query-api refuses to start on partial OR unreadable read-auth config (exit 2, event=config_validation_failed), no silent fall-through, no secret leak"
