#!/usr/bin/env bash
# M1-LOOP — the one-command Milestone-1 experience end to end: bring the
# consolidated stack up healthy with Prism served same-origin, then push the
# sample telemetry and see it across the three signals. The observable
# "bring it up, send, see it" loop (ADR-0077), driven by the project's own
# compose.yaml + Dockerfile.runtime + the seed (generator) service.
#
# Port-isolated: a catalogue compose override drops the OTLP ingest host ports
# (the seed reaches the runtime internally) and remaps the three query ports to
# high host ports, so M1-LOOP never collides with a separately-running canonical
# stack. Same-origin Prism is preserved (Prism + /api/v1 share one port).
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
SNAP="$HARNESS_DIR/.snapshot"
cp "$(dirname "$0")/compose.override.yaml" "$SNAP/compose.override.yaml"
cd "$SNAP"
PROJ="m1loop$$"
DC="docker compose -p $PROJ -f compose.yaml -f compose.override.yaml"

cleanup() { $DC --profile seed down -v >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "step: compose up (build runtime + Prism, start, wait healthy)"
$DC up -d --build --wait --wait-timeout 240 runtime > "$EVIDENCE_DIR/up.log" 2>&1 || { echo "compose up FAILED" >&2; tail -30 "$EVIDENCE_DIR/up.log" >&2; exit 1; }

S=$(( $(date -u +%s) - 300 )); E=$(( $(date -u +%s) + 300 ))
PR=$(curl -s -o "$EVIDENCE_DIR/prism.html" -w '%{http_code}' http://localhost:19390/ 2>/dev/null || echo 000)
QU=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:19390/api/v1/query_range?query=request_count&start=${S}&end=${E}&step=15s" 2>/dev/null || echo 000)
echo "prism_root=$PR query_up=$QU"

echo "step: seed (push sample telemetry via the generator service)"
$DC --profile seed run --rm --build -e SEED_FORCE=1 seed > "$EVIDENCE_DIR/seed.log" 2>&1 || { echo "seed FAILED" >&2; tail -30 "$EVIDENCE_DIR/seed.log" >&2; exit 1; }
sleep 3

M=$(curl -s "http://localhost:19390/api/v1/query_range?query=request_count&start=${S}&end=${E}&step=15s" | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["data"]["result"]))' 2>/dev/null || echo NA)
L=$(curl -s "http://localhost:19391/api/v1/logs?start=${S}&end=${E}&body_contains=declined" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(sum(1 for r in (d if isinstance(d,list) else []) if "declined" in str(r.get("body",""))))' 2>/dev/null || echo NA)
T=$(curl -s "http://localhost:19392/api/v1/traces?service=kaleidoscope-demo&start=${S}&end=${E}" | python3 -c 'import sys,json;s=json.load(sys.stdin);print(len(s) if isinstance(s,list) else 0)' 2>/dev/null || echo NA)
echo "demo_metrics=$M demo_logs=$L demo_traces=$T"

fail() { echo "FAIL: $1" >&2; exit 1; }
[ "$PR" = "200" ] || fail "Prism root :19390/ not 200 (got $PR) — same-origin Prism not served by the up stack"
grep -qiE '<!doctype html|<div id="root"|<html' "$EVIDENCE_DIR/prism.html" || fail ":19390/ did not return an HTML SPA document"
[ "$QU" = "200" ] || fail "query API not answering after up (got $QU)"
[ "$M" -ge 1 ] 2>/dev/null || fail "seed: request_count not queryable ($M series)"
[ "$L" -ge 1 ] 2>/dev/null || fail "seed: 'card declined' log not queryable ($L)"
[ "$T" -ge 1 ] 2>/dev/null || fail "seed: trace not queryable ($T spans)"

echo "M1LOOP satisfied — the stack comes up healthy with same-origin Prism (HTML on :9090) and the seed makes all three signals queryable (metrics $M, logs $L, traces $T). The one-command Milestone-1 loop holds."
