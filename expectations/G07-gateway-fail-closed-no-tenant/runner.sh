#!/usr/bin/env bash
# G07 — with NO default tenant configured, a record that carries no
# resource tenant.id is REFUSED (not silently dropped into a void).
# Covers UC-GWTEN-003 (fail-closed without a default tenant, ADR-0041
# Decision 2). Control: the SAME record IS accepted when a default tenant
# is configured, so the refusal is the no-tenant condition, not a broken
# gateway.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
TG="ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0"
boot() { # $1=name, rest=extra docker env args
    local name="$1"; shift
    docker run --rm -d --name "$name" -v "$DATA_HOST/$name:/data" -e RUST_LOG=info "$@" -p 14391:4318 "$GW_IMAGE" > /dev/null
    for i in $(seq 1 30); do docker logs "$name" 2>&1 | grep -q listener_bound && return 0; sleep 0.5; done
    echo "gateway $name never bound" >&2; return 1
}
send_no_tenant() { docker run --rm --network host "$TG" logs \
    --otlp-endpoint localhost:14391 --otlp-insecure --otlp-http --duration 1s --rate 2 --body "g07-probe"; }

mkdir -p "$DATA_HOST/g07-none" "$DATA_HOST/g07-default"

# Case 1: NO default tenant -> a no-tenant.id record must be refused.
boot g07-none || exit 1
NONE_EXIT=0; send_no_tenant > /tmp/none.out 2>&1 || NONE_EXIT=$?
echo "none_exit=$NONE_EXIT"
docker logs g07-none > "'"$EVIDENCE_DIR"'/none.gateway.stderr.txt" 2>&1 || true
cp /tmp/none.out "'"$EVIDENCE_DIR"'/none.telemetrygen.txt"
docker stop --time 5 g07-none >/dev/null 2>&1 || true

# Case 2 (control): default tenant set -> the SAME record is accepted.
boot g07-default -e KALEIDOSCOPE_DEFAULT_TENANT=acme || exit 1
DEF_EXIT=0; send_no_tenant > /tmp/def.out 2>&1 || DEF_EXIT=$?
echo "default_exit=$DEF_EXIT"
cp /tmp/def.out "'"$EVIDENCE_DIR"'/default.telemetrygen.txt"
docker stop --time 5 g07-default >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-gateway.sh" "$EVIDENCE_DIR" G07 "$INLINE"

OUT="$EVIDENCE_DIR/G07.stdout.txt"
val() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
# Fail-closed: the no-default ingest is refused (telemetrygen non-zero).
[[ "$(val none_exit)" != "0" ]] || { echo "no-default ingest was ACCEPTED (should be refused; silent void)" >&2; exit 1; }
# The gateway names the refusal reason (not a silent drop).
grep -qE 'no tenant|tenant\.id|refusing' "$EVIDENCE_DIR/none.gateway.stderr.txt" \
  || grep -qE 'no tenant|tenant\.id|refusing' "$EVIDENCE_DIR/none.telemetrygen.txt" \
  || { echo "refusal was not surfaced with a reason" >&2; tail -5 "$EVIDENCE_DIR/none.telemetrygen.txt" >&2; exit 1; }
# Control: with a default tenant the same record is accepted.
[[ "$(val default_exit)" == "0" ]] || { echo "control failed: the record was rejected even WITH a default tenant ($(val default_exit))" >&2; exit 1; }
echo "OK — no default tenant + a record with no tenant.id is REFUSED with a reason (fail-closed, not a silent void); the same record is ACCEPTED when a default tenant is configured"
