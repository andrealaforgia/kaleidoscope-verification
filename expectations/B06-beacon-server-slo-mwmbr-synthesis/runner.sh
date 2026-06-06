#!/usr/bin/env bash
# B06 — an operator [[slo]] declaration synthesises Multi-Window
# Multi-Burn-Rate rules that tick and emit incidents through the normal
# sink path (ADR-0067, beacon-slo-operator-path-v0).
#
# Previously the SLO engine was library-and-tests only (synthesise_slo had
# no caller outside the in-suite slice_05 test), so B06 was NOT black-box
# reachable (the assessment's "unreachable SLO engine"). The fix wires
# `[[slo]]` into the loader: a single SLO declaration is validated and
# expanded into FOUR MWMBR rules (page 1h/5m, page 6h/30m, ticket 1d/2h,
# ticket 3d/6h), each named `<service>_slo_<class>_<long>_<short>` with a
# `slo_service` label and the SLO's sinks. Now reachable end to end.
#
# Given a rules dir holding one `[[slo]]` (service b06svc, a webhook sink)
#       and a backend that reports the burn condition Active
# When beacon-server loads it and evaluates the synthesised rules
# Then the webhook receives Firing incidents from the SYNTHESISED MWMBR
#      rules (names `b06svc_slo_*`, label `slo_service=b06svc`), with more
#      than one distinct synthesised rule — the SLO fan-out.
set -euo pipefail
EVIDENCE_DIR="$1"
: "${HARNESS_DIR:?missing HARNESS_DIR}"
EXP_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_DIR="$HARNESS_DIR/.snapshot"

IMAGE="kaleidoscope-expectations/beacon-server:under-test"
NET="b06-net-$$"; MOCK="b06-mock"; BEACON="b06-beacon-$$"
OUT_HOST="$(mktemp -d -t b06-out-XXXXXX)"; : > "$OUT_HOST/incidents.ndjson"
RULES_HOST="$(mktemp -d -t b06-rules-XXXXXX)"; cp "$EXP_DIR/rules/"*.toml "$RULES_HOST/"

cleanup() {
    docker rm -f "$BEACON" "$MOCK" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
    rm -rf "$OUT_HOST" "$RULES_HOST"
}
trap cleanup EXIT

echo "step 1: build beacon-server" >&2
DOCKER_BUILDKIT=1 docker build --quiet \
    --build-context kaleidoscope="$SNAPSHOT_DIR" \
    -f "$HARNESS_DIR/Dockerfile.beacon-server" \
    -t "$IMAGE" "$HARNESS_DIR" > "$EVIDENCE_DIR/build.txt" 2>&1

docker network create "$NET" >/dev/null
docker run -d --name "$MOCK" --network "$NET" -e FIRING_WINDOW=1000 \
    -v "$EXP_DIR/mock/server.py:/mock/server.py:ro" -v "$OUT_HOST:/out" \
    python:3-slim python3 /mock/server.py >/dev/null
sleep 2
docker run -d --name "$BEACON" --network "$NET" \
    -e RUST_LOG=info -e NO_COLOR=1 \
    -v "$RULES_HOST:/rules" \
    "$IMAGE" --rules /rules --backend "http://${MOCK}:18091/api/v1" >/dev/null
sleep 38  # synthesised MWMBR rules have a fixed interval=30s (ADR-0067):
          # first tick sets Pending, the next (~30s) promotes to Firing.
docker logs "$BEACON" 2>&1 | sed $'s/\033\\[[0-9;]*m//g' > "$EVIDENCE_DIR/beacon-server.stderr.txt" || true
docker stop --time 3 "$BEACON" "$MOCK" >/dev/null 2>&1 || true
cp "$OUT_HOST/incidents.ndjson" "$EVIDENCE_DIR/incidents.ndjson" 2>/dev/null || true
echo "--- incidents captured ---" >&2; cat "$EVIDENCE_DIR/incidents.ndjson" >&2 || true
echo "--- beacon startup (rules_loaded counts the synthesised rules) ---" >&2
grep -E 'beacon-server starting|rules_loaded' "$EVIDENCE_DIR/beacon-server.stderr.txt" 2>/dev/null | head -2 >&2 || true

INC="$EVIDENCE_DIR/incidents.ndjson"

# 1. At least one Firing incident came from a SYNTHESISED SLO rule:
#    name `b06svc_slo_*` AND label slo_service=b06svc.
SLO_INC=$(jq -c 'select((.name|startswith("b06svc_slo_")) and (.labels.slo_service=="b06svc") and (.resolved_at==null))' "$INC" 2>/dev/null | head -1)
[[ -n "$SLO_INC" ]] || { echo "FAIL: no Firing incident from a synthesised SLO rule (name b06svc_slo_*, label slo_service=b06svc). The [[slo]] did not synthesise+emit." >&2; cat "$INC" >&2; echo "--- stderr ---" >&2; tail -20 "$EVIDENCE_DIR/beacon-server.stderr.txt" >&2; exit 1; }

# 2. The SLO fanned out: more than one distinct synthesised rule fired
#    (the MWMBR set is four; require >=2 to prove fan-out, tolerating tick
#    timing).
NDISTINCT=$(jq -r 'select((.name|startswith("b06svc_slo_")) and (.resolved_at==null)) | .name' "$INC" 2>/dev/null | sort -u | grep -c .)
[[ "$NDISTINCT" -ge 2 ]] || { echo "FAIL: only ${NDISTINCT} distinct synthesised SLO rule(s) fired (expected >=2 — the MWMBR fan-out from one [[slo]])" >&2; jq -r '.name' "$INC" 2>/dev/null | sort -u >&2; exit 1; }

NAMES=$(jq -r 'select(.name|startswith("b06svc_slo_")) | .name' "$INC" 2>/dev/null | sort -u | tr '\n' ' ')
echo "OK — one operator [[slo]] declaration synthesised Multi-Window Multi-Burn-Rate rules that fired through the sink path: ${NDISTINCT} distinct synthesised rules (${NAMES}) emitted Firing incidents to the webhook, each labelled slo_service=b06svc. The SLO engine is now operator-reachable (was the assessment's unreachable engine); ADR-0067 wired [[slo]] into the loader."
