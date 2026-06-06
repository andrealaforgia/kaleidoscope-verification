#!/usr/bin/env bash
# G06 — once live, the gateway's /healthz returns 200 (liveness SERVING)
# and /readyz returns 200 READY. Covers UC-GWHEALTH-002 (and confirms the
# readiness gate UC-GWHEALTH-006 e2e tests rely on).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
NAME="g06-$$"
docker run --rm -d --name "$NAME" -v "$DATA_HOST:/data" \
    -e KALEIDOSCOPE_DEFAULT_TENANT=acme -e RUST_LOG=info -p 14351:4318 "$GW_IMAGE" > /dev/null
for i in $(seq 1 30); do docker logs "$NAME" 2>&1 | grep -q listener_bound && break; sleep 0.5; done
sleep 1
echo "healthz_code=$(curl -sS --max-time 3 -o "'"$EVIDENCE_DIR"'/healthz.body" -w "%{http_code}" http://localhost:14351/healthz)"
echo "readyz_code=$(curl -sS --max-time 3 -o "'"$EVIDENCE_DIR"'/readyz.body" -w "%{http_code}" http://localhost:14351/readyz)"
docker stop --time 5 "$NAME" >/dev/null 2>&1 || true
'
"$HARNESS_DIR/run-gateway.sh" "$EVIDENCE_DIR" G06 "$INLINE"

OUT="$EVIDENCE_DIR/G06.stdout.txt"
val() { grep -oE "$1=[0-9]+" "$OUT" | tail -1 | cut -d= -f2; }
[[ "$(val healthz_code)" == "200" ]] || { echo "/healthz did not return 200 (got $(val healthz_code))" >&2; exit 1; }
[[ "$(val readyz_code)"  == "200" ]] || { echo "/readyz did not return 200 (got $(val readyz_code))" >&2; exit 1; }
[[ -s "$EVIDENCE_DIR/healthz.body" ]] || { echo "/healthz body was empty" >&2; exit 1; }
echo "OK — /healthz returns 200 (liveness, body: $(cat "$EVIDENCE_DIR/healthz.body")); /readyz returns 200 READY"
