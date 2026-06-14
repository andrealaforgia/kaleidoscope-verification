#!/usr/bin/env bash
# CR04 — tenant isolation inside the consolidated runtime (implementer msg 037).
# A metric ingested under tenant-a is NOT visible to a tenant-b-scoped query of
# the same shared live store, and vice versa. The single-process / live-Arc
# analogue of Q08 (which used separate gateway + query-api).
#
# Scenario (same pillar root):
#   1. boot `kaleidoscope` with KALEIDOSCOPE_TENANT=tenant-a. Ingest two metrics
#      to :4318: svcA under the default tenant (-> tenant-a) and svcB carrying an
#      explicit OTLP resource tenant.id=tenant-b (-> tenant-b, EG04 routing).
#   2. query metrics (router bound to tenant-a) -> 1 series (only svcA; the
#      tenant-b metric is isolated out, not leaked into the tenant-a view).
#   3. restart `kaleidoscope` over the SAME root with KALEIDOSCOPE_TENANT=tenant-b
#      -> query -> 1 series (only svcB). This both confirms svcB WAS ingested
#      (not dropped) and that tenant-a's svcA is isolated out of tenant-b's view.
#
# Transition-proof: RED if the tenant-a query sees the tenant-b metric (count != 1
# i.e. leak), or if the tenant-b query does not see its own metric (svcB dropped),
# or sees tenant-a's.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"

INLINE='
SHARED=$DATA_HOST/shared; mkdir -p "$SHARED"
RA="cr04-a-$$"; RB="cr04-b-$$"
cleanup() { docker stop --time 5 "$RA" "$RB" >/dev/null 2>&1 || true; docker rm "$RA" "$RB" >/dev/null 2>&1 || true; }
trap cleanup EXIT

S=$(date -u -v-5M +%s 2>/dev/null || date -u -d "-5 minutes" +%s); E=$(( $(date -u +%s) + 120 ))
mq() { curl -sS -o "$2" "http://localhost:$1/api/v1/query_range?query=gen&start=${S}&end=${E}&step=15s"; jq -r ".data.result|length" "$2" 2>/dev/null || echo NA; }
ready() { for _ in $(seq 1 40); do [[ "$(curl -sS -o /dev/null -w "%{http_code}" "http://localhost:$1/api/v1/query_range?query=gen&start=${S}&end=${E}&step=15s" 2>/dev/null)" == "200" ]] && return 0; sleep 1; done; return 1; }
tgen() { docker run --rm --network host ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.114.0 "$@" >/dev/null 2>&1; }

# 1. consolidated runtime bound to tenant-a.
docker run --rm -d --name "$RA" -v "$SHARED:/data" -e KALEIDOSCOPE_TENANT=tenant-a -e RUST_LOG=info -p 14336:4318 -p 19120:9090 "$CRT_IMAGE" > /dev/null
ready 19120 || { echo "runtime(a) never ready" >&2; docker logs "$RA" >&2 || true; exit 1; }
# svcA -> default tenant (tenant-a, distinct service.name); the second metric
# carries ONLY an explicit resource tenant.id=tenant-b (EG04-proven single-attr
# form) -> routes to tenant-b. If routing works: tenant-a sees just svcA (1),
# tenant-b sees the default-service gen (1). If tenant.id is ignored, the second
# metric falls into tenant-a with the default service.name -> tenant-a = 2.
tgen metrics --otlp-endpoint localhost:14336 --otlp-insecure --otlp-http --duration 1s --rate 1 --otlp-attributes service.name=\"cr04-svcA\"
tgen metrics --otlp-endpoint localhost:14336 --otlp-insecure --otlp-http --duration 1s --rate 1 --otlp-attributes tenant.id=\"tenant-b\"
# settle, then query tenant-a.
TA=0; for _ in $(seq 1 15); do TA=$(mq 19120 "'"$EVIDENCE_DIR"'/tenant_a.json"); [[ "$TA" =~ ^[0-9]+$ && "$TA" -ge 1 ]] && break; sleep 1; done
echo "tenant_a_view=${TA}"
docker stop --time 5 "$RA" >/dev/null 2>&1 || true; docker rm "$RA" >/dev/null 2>&1 || true

# 3. restart over the same root, bound to tenant-b.
docker run --rm -d --name "$RB" -v "$SHARED:/data" -e KALEIDOSCOPE_TENANT=tenant-b -e RUST_LOG=info -p 14337:4318 -p 19121:9090 "$CRT_IMAGE" > /dev/null
ready 19121 || { echo "runtime(b) never ready" >&2; docker logs "$RB" >&2 || true; exit 1; }
TB=0; for _ in $(seq 1 15); do TB=$(mq 19121 "'"$EVIDENCE_DIR"'/tenant_b.json"); [[ "$TB" =~ ^[0-9]+$ && "$TB" -ge 1 ]] && break; sleep 1; done
echo "tenant_b_view=${TB}"
'
"$HARNESS_DIR/run-kaleidoscope-runtime.sh" "$EVIDENCE_DIR" CR04 "$INLINE"

OUT="$EVIDENCE_DIR/CR04.stdout.txt"
f() { grep -oE "$1=[^ ]+" "$OUT" | tail -1 | cut -d= -f2; }
fail() { echo "FAIL: $1" >&2; cat "$OUT" >&2; exit 1; }

TA=$(f tenant_a_view); TB=$(f tenant_b_view)
[[ "$TA" == "1" ]] || fail "tenant-a query returned $TA series (expected exactly 1 = svcA only). If 2, the tenant-b metric LEAKED into the tenant-a view (isolation breach); if 0, svcA was not ingested"
[[ "$TB" == "1" ]] || fail "tenant-b query returned $TB series (expected exactly 1 = svcB only). If 0, the explicit tenant.id=tenant-b metric was dropped; if 2, tenant-a's svcA leaked into tenant-b"
echo "CR04 satisfied — tenant isolation in the consolidated runtime's shared store: tenant-a sees only svcA (1 series, the tenant-b metric isolated out), tenant-b sees only svcB (1 series). No cross-tenant leak either direction."
